import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfDocument;

import '../errors.dart';
import '../file_io.dart' show uniqueDestination, atomicWriteBytes;

/// Output image format for PDF → Images.
enum PdfToImagesFormat { png, jpeg }

final class PdfToImagesArgs {
  const PdfToImagesArgs({
    required this.inputPath,
    required this.outputDir,
    required this.pages,
    required this.format,
    required this.dpi,
  });

  final String inputPath;
  final String outputDir;

  /// 1-based page numbers to render (validated against the document).
  final List<int> pages;

  final PdfToImagesFormat format;

  /// Render resolution in dots per inch (72 = 1× PDF point size).
  final int dpi;
}

final class PdfToImagesResult {
  const PdfToImagesResult({
    required this.outputPath,
    required this.outputBytes,
    required this.imageCount,
    required this.pageCountTotal,
  });

  /// A single image when one page was rendered, otherwise a zip of the
  /// images (edge #36).
  final String outputPath;
  final int outputBytes;
  final int imageCount;

  /// Total page count of the source document (shown on the result screen).
  final int pageCountTotal;
}

/// Rendering source abstraction: the app wires [pdfxPageRenderer] (platform
/// channels), tests wire a fake. Returns (pageWidthPt, pageHeightPt, bytes).
typedef PageRenderer = Future<(double, double, Uint8List)> Function(
  String inputPath,
  int pageNumber, // 1-based
  int renderWidthPx,
  int renderHeightPx,
  PdfToImagesFormat format,
  int dpi,
);

/// pdfx-based renderer used on device. Platform channels require the host
/// isolate's token, which the job runner injects.
Future<(double, double, Uint8List)> pdfxPageRenderer(
  String inputPath,
  int pageNumber,
  int renderWidthPx,
  int renderHeightPx,
  PdfToImagesFormat format,
  int dpi,
) async {
  final doc = await pdfx.PdfDocument.openData(File(inputPath).readAsBytesSync());
  try {
    final page = await doc.getPage(pageNumber);
    try {
      final image = await page.render(
        width: renderWidthPx.toDouble(),
        height: renderHeightPx.toDouble(),
        format: format == PdfToImagesFormat.png
            ? pdfx.PdfPageImageFormat.png
            : pdfx.PdfPageImageFormat.jpeg,
        quality: 90,
        backgroundColor: '#FFFFFF',
      );
      if (image == null || image.bytes.isEmpty) {
        throw CorruptedFile(fileName: _nameOf(inputPath), detail: 'Page render failed');
      }
      return (page.width, page.height, Uint8List.fromList(image.bytes));
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

String _nameOf(String path) => path.split(Platform.pathSeparator).last;

/// PDF → Images task — runs inside the job isolate with [renderer] injected
/// by the caller (pdfx on device, a stub in tests).
Future<PdfToImagesResult> pdfToImagesTask(
  PdfToImagesArgs args, {
  required PageRenderer renderer,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final name = _nameOf(args.inputPath);

  // Probe the document: typed errors for encrypted (pdfx cannot open those
  // on Android — password support is web-only) and corrupt files, plus the
  // page count and per-page sizes used for render scaling.
  final (pageCount, pageSizes) = _probe(args.inputPath, name);

  // Empty selection = every page; otherwise clamp to real pages, ascending.
  final requested = args.pages.isEmpty
      ? List<int>.generate(pageCount, (i) => i + 1)
      : args.pages;
  final wanted = {...requested}.where((p) => p >= 1 && p <= pageCount).toList()..sort();
  if (wanted.isEmpty) {
    throw UnsupportedFormat(
      fileName: name,
      expected: 'a selection of at least one existing page',
    );
  }

  final stem = _stemOf(name);
  if (wanted.length == 1) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final pageNo = wanted.single;
    onProgress?.call(0.5, 'Page $pageNo');

    final (wPt, hPt) = pageSizes[pageNo - 1];
    final scale = args.dpi / 72.0;
    final widthPx = (wPt * scale).round().clamp(1, 4096);
    final heightPx = (hPt * scale).round().clamp(1, 4096);

    final (_, _, bytes) = await renderer(args.inputPath, pageNo, widthPx, heightPx, args.format, args.dpi);
    final ext = args.format == PdfToImagesFormat.png ? 'png' : 'jpg';
    final target = uniqueDestination(args.outputDir, '$stem p$pageNo.$ext');
    await atomicWriteBytes(target, bytes);
    onProgress?.call(1.0, null);
    return PdfToImagesResult(
      outputPath: target,
      outputBytes: bytes.length,
      imageCount: 1,
      pageCountTotal: pageCount,
    );
  }

  final images = <(String, Uint8List)>[];
  for (var i = 0; i < wanted.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final pageNo = wanted[i];
    onProgress?.call(i / wanted.length, 'Page $pageNo');

    final (wPt, hPt) = pageSizes[pageNo - 1];
    final scale = args.dpi / 72.0;
    final widthPx = (wPt * scale).round().clamp(1, 4096);
    final heightPx = (hPt * scale).round().clamp(1, 4096);

    final (_, _, bytes) = await renderer(args.inputPath, pageNo, widthPx, heightPx, args.format, args.dpi);
    final ext = args.format == PdfToImagesFormat.png ? 'png' : 'jpg';
    images.add(('$stem p$pageNo.$ext', bytes));
  }

  onProgress?.call(wanted.length / wanted.length, 'Packing zip');
  final archive = Archive();
  for (final (fileName, data) in images) {
    archive.add(ArchiveFile(fileName, data.length, data));
  }
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final zipTarget = uniqueDestination(args.outputDir, '$stem images.zip');
  await atomicWriteBytes(zipTarget, zipBytes);
  return PdfToImagesResult(
    outputPath: zipTarget,
    outputBytes: zipBytes.length,
    imageCount: images.length,
    pageCountTotal: pageCount,
  );
}

/// Opens the file once to validate it and read page geometry.
(int, List<(double, double)>) _probe(String path, String name) {
  PdfDocument? probe;
  try {
    probe = PdfDocument(inputBytes: File(path).readAsBytesSync());
    final pageCount = probe.pages.count;
    if (pageCount == 0) {
      throw CorruptedFile(fileName: name, detail: 'This PDF has no pages');
    }
    final sizes = <(double, double)>[];
    for (var i = 0; i < pageCount; i++) {
      final s = probe.pages[i].size;
      sizes.add((s.width, s.height));
    }
    return (pageCount, sizes);
  } on PureError {
    rethrow;
  } on Object catch (e) {
    // syncfusion throws Errors (ArgumentError etc.), not Exceptions.
    final msg = e.toString().toLowerCase();
    if (msg.contains('encrypt') || msg.contains('password')) {
      throw UnsupportedFormat(
        fileName: name,
        expected: 'an unencrypted PDF — password-protected files are not supported here',
      );
    }
    throw CorruptedFile(fileName: name, detail: 'The PDF structure is damaged');
  } finally {
    probe?.dispose();
  }
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
