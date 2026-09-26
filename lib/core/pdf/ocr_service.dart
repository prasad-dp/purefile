import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination;

/// One recognized text element with its position in the rendered page image.
final class OcrElement {
  const OcrElement({required this.text, required this.box});
  final String text;

  /// Box in pixels of the rendered page image (origin = top-left).
  final Rect box;
}

/// Rendering source: the device wires the ML Kit implementation, tests wire a
/// stub — same injection pattern as the F6 renderer.
typedef PageRecognizer = Future<List<OcrElement>> Function(
  Uint8List pageImageBytes,
);

/// Raster source: pdfx-based on device, stub in tests. Returns
/// (pageWidthPt, pageHeightPx, imageBytes) — bytes are PNG.
typedef PageRaster = Future<(double, double, Uint8List)> Function(
  String inputPath,
  int pageNumber, // 1-based
);

/// OCR result for one finished job.
final class OcrResult {
  const OcrResult({
    required this.outputPath,
    required this.outputBytes,
    required this.textPath,
    required this.textBytes,
    required this.pageCount,
    required this.noText,
  });

  /// The searchable PDF (page image + invisible text layer).
  final String outputPath;
  final int outputBytes;

  /// Plain-text companion file.
  final String textPath;
  final int textBytes;
  final int pageCount;

  /// True when no text was recognized on any page (edge #25).
  final bool noText;
}

final class OcrArgs {
  const OcrArgs({
    required this.inputPath,
    required this.outputDir,
    this.pages = const [],
  });

  final String inputPath;
  final String outputDir;

  /// 1-based page selection; empty = all pages.
  final List<int> pages;
}

/// OCR pipeline:
/// 1. Probe the document (encrypted → [PasswordRequired], corrupt →
///    [CorruptedFile], zero pages → [CorruptedFile]).
/// 2. Per selected page: rasterize via [renderPage], recognize via [recognize].
/// 3. Output PDF: one page per source page — the rasterized image PLUS the
///    recognized text drawn with an **alpha-0 brush** at the recognized
///    positions (invisible, but real PDF text: searchable + copy-pastable).
/// 4. Companion `.txt` with per-page sections.
///
/// Selection entries outside the page range are clamped away; a selection
/// that is entirely out of range throws [UnsupportedFormat].
Future<OcrResult> ocrTask(
  OcrArgs args, {
  required PageRecognizer recognize,
  required PageRaster renderPage,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  // 0. Probe.
  final pdfBytes = File(args.inputPath).readAsBytesSync();
  int pageCount;
  try {
    final probe = PdfDocument(inputBytes: pdfBytes);
    pageCount = probe.pages.count;
    probe.dispose();
  } on ArgumentError catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw PasswordRequired(fileName: args.inputPath);
    }
    throw CorruptedFile(fileName: args.inputPath);
  } on Exception {
    throw CorruptedFile(fileName: args.inputPath);
  }
  if (pageCount == 0) {
    throw CorruptedFile(fileName: args.inputPath, detail: 'no pages');
  }

  final selection = _normalizeSelection(args.pages, pageCount);
  if (selection.isEmpty) {
    throw UnsupportedFormat(
      fileName: args.inputPath,
      expected: 'at least one page in 1–$pageCount',
    );
  }

  final stem = _stemOf(args.inputPath);
  final outDoc = PdfDocument();
  final textBuf = StringBuffer();
  var anyText = false;
  final sections = outDoc.sections!;

  try {
    var done = 0;
    for (final pageNumber in selection) {
      if (isCancelled?.call() ?? false) throw const JobCancelled();
      onProgress?.call(done / selection.length, 'Page $pageNumber of ${selection.length}');

      // 1. Rasterize.
      final (wPt, hPt, imageBytes) =
          await renderPage(args.inputPath, pageNumber);

      // 2. Recognize.
      final elements = await recognize(imageBytes);
      if (elements.isNotEmpty) anyText = true;

      // 3. Output page: one section per page, size set exactly once (F3
      //    lesson: later size writes on a section are silently ignored).
      final section = sections.add();
      if (wPt > hPt) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      }
      section.pageSettings.size = Size(wPt, hPt);
      final page = section.pages.add();
      page.graphics.drawImage(PdfBitmap(imageBytes), Rect.fromLTWH(0, 0, wPt, hPt));

      // Invisible text layer at the recognized positions.
      if (elements.isNotEmpty) {
        for (final e in elements) {
          final rect = Rect.fromLTWH(
            e.box.left / _renderScale,
            e.box.top / _renderScale,
            e.box.width / _renderScale,
            e.box.height / _renderScale,
          );
          final size = (rect.height * 0.8).clamp(2.0, 24.0);
          page.graphics.drawString(
            e.text,
            PdfStandardFont(PdfFontFamily.helvetica, size),
            brush: PdfSolidBrush(PdfColor(0, 0, 0, 0)),
            bounds: rect,
          );
        }
      }

      textBuf.writeln('--- Page $pageNumber ---');
      textBuf.writeln(
          elements.isEmpty ? '[No text found on this page]' : _joinText(elements));
      done++;
    }

    final pdfOut = Uint8List.fromList(outDoc.saveSync());

    // 4. Outputs (unique, never overwrite).
    final pdfPath =
        uniqueDestination(args.outputDir, '$stem ocr.pdf');
    File(pdfPath).writeAsBytesSync(pdfOut, flush: true);
    final textPath =
        uniqueDestination(args.outputDir, '$stem ocr.txt');
    File(textPath).writeAsBytesSync(
      Uint8List.fromList(textBuf.toString().codeUnits),
      flush: true,
    );

    return OcrResult(
      outputPath: pdfPath,
      outputBytes: pdfOut.length,
      textPath: textPath,
      textBytes: textBuf.length,
      pageCount: selection.length,
      noText: !anyText,
    );
  } finally {
    outDoc.dispose();
  }
}

/// The raster side renders at this many pixels per PDF point. Recognized
/// pixel boxes are mapped back to page points with it.
const double _renderScale = 200 / 72;

String _joinText(List<OcrElement> elements) {
  final buf = StringBuffer();
  var lastBottom = -1.0;
  for (final e in elements) {
    if (lastBottom >= 0 && (e.box.top - lastBottom).abs() > 12) {
      buf.write('\n');
    } else if (buf.isNotEmpty) {
      buf.write(' ');
    }
    buf.write(e.text);
    lastBottom = e.box.top;
  }
  return buf.toString();
}

List<int> _normalizeSelection(List<int> pages, int pageCount) {
  if (pages.isEmpty) {
    return List<int>.generate(pageCount, (i) => i + 1);
  }
  final s =
      pages.where((p) => p >= 1 && p <= pageCount).toSet().toList()..sort();
  return s;
}

String _stemOf(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
