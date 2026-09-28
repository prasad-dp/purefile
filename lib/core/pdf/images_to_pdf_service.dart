import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination, atomicWriteBytes;

/// How each image maps onto its PDF page.
enum ImageFit {
  /// One page per image, page = image pixel size (exact 1:1, no scaling).
  imageSize,

  /// Standard A4 pages (595×842 pt); the image is centered inside the
  /// printable area with its aspect ratio preserved. Landscape A4 is used
  /// automatically for wide images.
  a4,
}

final class ImagesToPdfArgs {
  const ImagesToPdfArgs({
    required this.images,
    required this.outputDir,
    this.fit = ImageFit.imageSize,
    this.outputFileName,
  });

  /// Ordered images (user-reorderable) as (path, name).
  final List<(String path, String name)> images;
  final String outputDir;
  final ImageFit fit;
  final String? outputFileName;
}

final class ImagesToPdfResult {
  const ImagesToPdfResult({required this.outputPath, required this.outputBytes, required this.pageCount});

  final String outputPath;
  final int outputBytes;
  final int pageCount;
}

/// Images → PDF task — runs inside the job isolate.
///
/// Every image is decoded and its EXIF orientation baked (phone photos
/// otherwise render sideways in the PDF). JPEGs re-encode at quality 95
/// (visually lossless); PNG/WebP re-encode as PNG (lossless, transparency
/// flattens onto the white page). One corrupt image is skipped and reported;
/// if none survive, the job fails with a typed error and no output (same
/// partial-success contract as the merge service).
Future<ImagesToPdfResult> imagesToPdfTask(
  ImagesToPdfArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final built = PdfDocument();
  built.fileStructure.incrementalUpdate = false;
  built.fileStructure.crossReferenceType = PdfCrossReferenceType.crossReferenceStream;
  final failed = <String>[];
  var pages = 0;

  try {
    for (var i = 0; i < args.images.length; i++) {
      if (isCancelled?.call() ?? false) throw const JobCancelled();
      final (path, name) = args.images[i];
      onProgress?.call(i / args.images.length, 'Adding $name');

      try {
        final bytes = File(path).readAsBytesSync();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw CorruptedFile(fileName: name, detail: 'Unreadable image data');
        }
        // Bake EXIF rotation so the PDF shows what the user sees.
        final baked = img.bakeOrientation(decoded);
        final embedData = _embeddableData(baked, name);
        switch (args.fit) {
          case ImageFit.imageSize:
            _addExactPage(built, baked, embedData);
          case ImageFit.a4:
            _addA4Page(built, baked, embedData);
        }
        pages++;
      } on PureError catch (e) {
        if (e is JobCancelled) rethrow;
        // One unreadable image must not sink the batch — skip and report.
        failed.add(name);
      } on Object catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('cancel')) rethrow;
        failed.add(name);
      }
    }

    if (pages == 0) {
      throw CorruptedFile(
        fileName: args.images.first.$2,
        detail: 'No image could be read',
      );
    }

    onProgress?.call(0.95, 'Saving');
    final stem = _stemOf(args.images.first.$2);
    final defaultName = pages == 1 ? '$stem.pdf' : '${stem}_plus${pages - 1}.pdf';
    final targetName = (args.outputFileName != null && args.outputFileName!.trim().isNotEmpty)
        ? (args.outputFileName!.trim().toLowerCase().endsWith('.pdf')
            ? args.outputFileName!.trim()
            : '${args.outputFileName!.trim()}.pdf')
        : defaultName;
    final target = uniqueDestination(args.outputDir, targetName);
    final bytes = Uint8List.fromList(await built.save());
    await atomicWriteBytes(target, bytes);
    return ImagesToPdfResult(
      outputPath: target,
      outputBytes: bytes.length,
      pageCount: pages,
    );
  } finally {
    built.dispose();
  }
}

/// Page sized exactly to the image; image drawn 1:1 (no interpolation blur).
void _addExactPage(PdfDocument built, img.Image decoded, Uint8List embedData) {
  final w = decoded.width.toDouble();
  final h = decoded.height.toDouble();
  final section = built.sections!.add();
  if (w > h) section.pageSettings.orientation = PdfPageOrientation.landscape;
  section.pageSettings.size = Size(w, h);
  _drawOnPage(section.pages.add(), embedData, Rect.fromLTWH(0, 0, w, h));
}

/// Landscape/portrait A4 chosen from the image's aspect; image centered at
/// full printable area, aspect preserved (letterboxing, no crop).
void _addA4Page(PdfDocument built, img.Image decoded, Uint8List embedData) {
  const a4 = Size(595, 842);
  final landscape = decoded.width > decoded.height;
  final pageW = landscape ? a4.height : a4.width;
  final pageH = landscape ? a4.width : a4.height;

  final scale = (pageW / decoded.width).clamp(0.0, pageH / decoded.height);
  final drawW = decoded.width * scale;
  final drawH = decoded.height * scale;
  final dx = (pageW - drawW) / 2;
  final dy = (pageH - drawH) / 2;

  final section = built.sections!.add();
  if (landscape) section.pageSettings.orientation = PdfPageOrientation.landscape;
  section.pageSettings.size = Size(pageW, pageH);
  _drawOnPage(
    section.pages.add(),
    embedData,
    Rect.fromLTWH(dx, dy, drawW, drawH),
  );
}

void _drawOnPage(PdfPage page, Uint8List embedData, Rect bounds) {
  page.graphics.drawRectangle(brush: PdfBrushes.white, bounds: bounds); // edge #24
  page.graphics.drawImage(PdfBitmap(embedData), bounds);
}

/// JPEG re-encodes at 95 (visually lossless, orientation now real);
/// everything else re-encodes as PNG (lossless).
Uint8List _embeddableData(img.Image baked, String name) {
  final lower = name.toLowerCase();
  final isJpeg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');
  return Uint8List.fromList(
    isJpeg ? img.encodeJpg(baked, quality: 95) : img.encodePng(baked),
  );
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
