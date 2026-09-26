import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination;

/// One input to merge, in user-chosen order.
final class MergeItem {
  const MergeItem({required this.path, required this.name, required this.isPdf});

  final String path;
  final String name;

  /// true = PDF document, false = image (JPG/PNG/WebP).
  final bool isPdf;
}

final class MergeArgs {
  const MergeArgs({required this.items, required this.outputDir, this.password});

  /// Ordered items (user reorderable — F10).
  final List<MergeItem> items;
  final String outputDir;

  /// Optional password applied when opening encrypted PDF items (v1: one
  /// password for all items; per-item passwords come with the password UI).
  final String? password;
}

final class MergeResult {
  const MergeResult({required this.outputPath, required this.outputBytes, required this.failedNames});

  final String outputPath;
  final int outputBytes;

  /// Items that could not be merged (corrupt/encrypted) — the merge still
  /// succeeded with the rest. Empty = full success.
  final List<String> failedNames;
}

/// Merge PDF task — runs inside the job isolate (F10).
///
/// PDF items contribute their pages 1:1 via page templates (no re-encoding).
/// Image items become a white page sized to the image; JPEGs are embedded
/// directly, everything else is re-encoded as PNG.
/// If every item fails the merge throws the first error; a partial failure
/// is reported in [MergeResult.failedNames] (edge case #10 behavior).
Future<MergeResult> pdfMergeTask(
  MergeArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (args.items.isEmpty) {
    throw const UnsupportedFormat(fileName: 'Nothing selected', expected: 'at least one file');
  }

  final built = PdfDocument();
  var mergedCount = 0;
  final failed = <String>[];
  Object? firstError;

  try {
    built.fileStructure.incrementalUpdate = false;
    built.fileStructure.crossReferenceType = PdfCrossReferenceType.crossReferenceStream;

    for (var i = 0; i < args.items.length; i++) {
      if (isCancelled?.call() ?? false) throw const JobCancelled();
      final item = args.items[i];
      onProgress?.call(i / args.items.length, 'Merging ${item.name}');
      try {
        if (item.isPdf) {
          mergedCount += _appendPdf(built, item, args.password);
        } else {
          _appendImage(built, item);
          mergedCount++;
        }
      } on PureError {
        rethrow;
      } on Object catch (e) {
        final msg = e.toString().toLowerCase();
        final encryptedLike = msg.contains('encrypt') || msg.contains('password');
        if (encryptedLike && args.password == null) {
          // Edge #18: ask for a password instead of silently skipping.
          throw PasswordRequired(fileName: item.name);
        }
        if (encryptedLike) {
          firstError ??= const WrongPassword();
        }
        // One corrupt item must not sink the merge — skip and report.
        failed.add(item.name);
      }
    }

    if (mergedCount == 0) {
      throw firstError ??
          CorruptedFile(fileName: args.items.first.name, detail: 'No item could be read');
    }

    onProgress?.call(0.9, 'Saving');
    final target = uniqueDestination(args.outputDir, 'merged.pdf');
    final bytes = await built.save();
    await _atomicWrite(target, Uint8List.fromList(bytes));
    return MergeResult(outputPath: target, outputBytes: bytes.length, failedNames: failed);
  } finally {
    built.dispose();
  }
}

int _appendPdf(PdfDocument built, MergeItem item, String? password) {
  final bytes = File(item.path).readAsBytesSync();
  final src = PdfDocument(inputBytes: bytes, password: password);
  try {
    if (src.pages.count == 0) {
      throw CorruptedFile(fileName: item.name, detail: 'This PDF has no pages');
    }
    // One section PER PAGE, size set exactly once before the page is added.
    // (The section.pageSettings getter flips isPageAdded once pages exist,
    // so later size assignments on the same section are silently ignored —
    // per-page sections keep mixed page sizes correct.)
    for (var p = 0; p < src.pages.count; p++) {
      final srcPage = src.pages[p];
      final template = srcPage.createTemplate();
      final w = srcPage.size.width;
      final h = srcPage.size.height;
      final section = built.sections!.add();
      // Syncfusion stores portrait sizes as (min,max); request landscape
      // orientation first so (w,h) is kept verbatim for wide pages.
      if (w > h) section.pageSettings.orientation = PdfPageOrientation.landscape;
      section.pageSettings.size = Size(w, h);
      final page = section.pages.add();
      page.graphics.drawPdfTemplate(template, Offset.zero, Size(w, h));
    }
    return src.pages.count;
  } finally {
    src.dispose();
  }
}

void _appendImage(PdfDocument built, MergeItem item) {
  final bytes = File(item.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw CorruptedFile(fileName: item.name, detail: 'Unreadable image data');
  }

  final isJpeg = item.name.toLowerCase().endsWith('.jpg') ||
      item.name.toLowerCase().endsWith('.jpeg');
  final Uint8List embedData;
  if (isJpeg) {
    // JPEGs embed as-is (no re-encode, no quality loss).
    embedData = bytes;
  } else {
    // PNG/WebP re-encode as PNG; transparency flattens onto the white page.
    embedData = Uint8List.fromList(img.encodePng(decoded));
  }

  final w = decoded.width.toDouble();
  final h = decoded.height.toDouble();
  final section = built.sections!.add();
  if (w > h) section.pageSettings.orientation = PdfPageOrientation.landscape;
  section.pageSettings.size = Size(w, h);
  final page = section.pages.add();
  // Flatten transparent images onto white (edge #24).
  page.graphics.drawRectangle(
    brush: PdfBrushes.white,
    bounds: Rect.fromLTWH(0, 0, w, h),
  );
  page.graphics.drawImage(
    PdfBitmap(embedData),
    Rect.fromLTWH(0, 0, w, h),
  );
}

Future<void> _atomicWrite(String targetPath, Uint8List bytes) async {
  final temp = File('$targetPath.pf-tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(targetPath);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}
