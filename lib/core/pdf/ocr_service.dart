import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination;
import '../scan/scan_processing.dart' show enhanceDocument;

/// One recognized text element with its position in the rendered page image.
final class OcrElement {
  const OcrElement({
    required this.text,
    required this.box,
    this.blockIndex = 0,
    this.confidence,
  });

  final String text;

  /// Box in pixels of the rendered page image (origin = top-left).
  final Rect box;

  /// Logical block/paragraph grouping index from recognizer.
  final int blockIndex;

  /// Recognition confidence score (0.0 to 1.0) when available.
  final double? confidence;
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
    this.extractedText = '',
    this.wordCount = 0,
    this.characterCount = 0,
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

  /// Full aggregated plain text extracted from the document.
  final String extractedText;

  /// Total word count recognized.
  final int wordCount;

  /// Total character count recognized.
  final int characterCount;
}

final class OcrArgs {
  const OcrArgs({
    this.inputPath = '',
    this.imagePaths = const [],
    required this.outputDir,
    this.pages = const [],
    this.script = 'latin',
    this.enhanceImage = true,
    this.preserveLayout = true,
  });

  /// Single PDF or image input path.
  final String inputPath;

  /// Multi-image input paths (for batch images -> single multi-page searchable PDF).
  final List<String> imagePaths;

  final String outputDir;

  /// 1-based page selection (PDFs only); empty = all pages.
  final List<int> pages;

  /// Recognition script ('latin', 'chinese', 'devanagari', 'japanese', 'korean').
  final String script;

  /// Whether to enhance lighting, contrast, and paper cleanliness prior to OCR.
  final bool enhanceImage;

  /// Whether to preserve natural paragraph breaks and column reading order.
  final bool preserveLayout;
}

/// The raster side renders at this many pixels per PDF point. Recognized
/// pixel boxes are mapped back to page points with it.
const double _renderScale = 200 / 72;

/// Top-notch OCR pipeline:
/// - Supports both PDF documents and direct Images (JPG, PNG, WebP, HEIC).
/// - Supports multi-image batching into a single multi-page Searchable PDF.
/// - Applies document contrast & shadow lifting for maximum text accuracy.
/// - Produces a Dual-Layer Searchable PDF (crisp image + invisible selectable text).
/// - Layout-aware text reconstruction preserving paragraphs, columns, and reading order.
/// - Companion `.txt` file and extracted text statistics.
Future<OcrResult> ocrTask(
  OcrArgs args, {
  required PageRecognizer recognize,
  required PageRaster renderPage,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() ?? false) throw const JobCancelled();

  if (args.imagePaths.length > 1) {
    return _processMultiImageOcr(
      args,
      recognize: recognize,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  final effectivePath =
      args.imagePaths.isNotEmpty ? args.imagePaths.first : args.inputPath;

  final file = File(effectivePath);
  if (!file.existsSync()) {
    throw CorruptedFile(fileName: effectivePath, detail: 'file missing');
  }

  final inputBytes = file.readAsBytesSync();
  if (inputBytes.isEmpty) {
    throw CorruptedFile(fileName: effectivePath, detail: 'empty file');
  }

  final isPdf = _isPdfBytes(inputBytes);
  final effectiveArgs = args.inputPath != effectivePath
      ? OcrArgs(
          inputPath: effectivePath,
          outputDir: args.outputDir,
          pages: args.pages,
          script: args.script,
          enhanceImage: args.enhanceImage,
          preserveLayout: args.preserveLayout,
        )
      : args;

  if (isPdf) {
    return _processPdfOcr(
      effectiveArgs,
      inputBytes: inputBytes,
      recognize: recognize,
      renderPage: renderPage,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  } else {
    return _processImageOcr(
      effectiveArgs,
      imageBytes: inputBytes,
      recognize: recognize,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

Future<OcrResult> _processMultiImageOcr(
  OcrArgs args, {
  required PageRecognizer recognize,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final outDoc = PdfDocument();
  final textBuf = StringBuffer();
  final allExtractedBuf = StringBuffer();
  var anyText = false;
  final sections = outDoc.sections!;

  try {
    var done = 0;
    final total = args.imagePaths.length;
    for (final imgPath in args.imagePaths) {
      if (isCancelled?.call() ?? false) throw const JobCancelled();
      final pageNumber = done + 1;
      onProgress?.call(done / total, 'Image $pageNumber of $total');

      final file = File(imgPath);
      if (!file.existsSync()) {
        throw CorruptedFile(fileName: imgPath, detail: 'missing image');
      }
      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw CorruptedFile(fileName: imgPath, detail: 'unsupported image');
      }

      final Uint8List bytesForOcr;
      if (args.enhanceImage) {
        bytesForOcr = _tryEnhanceImageBytes(rawBytes);
      } else {
        bytesForOcr = rawBytes;
      }

      final elements = await recognize(bytesForOcr);
      if (elements.isNotEmpty) anyText = true;

      final wPt = decoded.width / _renderScale;
      final hPt = decoded.height / _renderScale;

      final section = sections.add();
      if (wPt > hPt) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      }
      section.pageSettings.size = Size(wPt, hPt);
      final page = section.pages.add();

      page.graphics.drawImage(PdfBitmap(rawBytes), Rect.fromLTWH(0, 0, wPt, hPt));

      if (elements.isNotEmpty) {
        _drawInvisibleTextLayer(page, elements);
      }

      final pageText = formatOcrText(elements, preserveLayout: args.preserveLayout);

      textBuf.writeln('--- Page $pageNumber (${_stemOf(imgPath)}) ---');
      textBuf.writeln(
          elements.isEmpty ? '[No text found on this page]' : pageText);

      if (elements.isNotEmpty) {
        if (allExtractedBuf.isNotEmpty) allExtractedBuf.write('\n\n');
        allExtractedBuf.write(pageText);
      }

      done++;
    }

    final stem = args.imagePaths.isNotEmpty
        ? _stemOf(args.imagePaths.first)
        : 'ocr_document';

    final pdfOut = Uint8List.fromList(outDoc.saveSync());
    final fullText = allExtractedBuf.toString();

    final pdfPath = uniqueDestination(args.outputDir, '$stem ocr.pdf');
    File(pdfPath).writeAsBytesSync(pdfOut, flush: true);
    final textPath = uniqueDestination(args.outputDir, '$stem ocr.txt');
    final textFileBytes = Uint8List.fromList(textBuf.toString().codeUnits);
    File(textPath).writeAsBytesSync(textFileBytes, flush: true);

    return OcrResult(
      outputPath: pdfPath,
      outputBytes: pdfOut.length,
      textPath: textPath,
      textBytes: textFileBytes.length,
      pageCount: total,
      noText: !anyText,
      extractedText: fullText,
      wordCount: _countWords(fullText),
      characterCount: fullText.length,
    );
  } finally {
    outDoc.dispose();
  }
}

Future<OcrResult> _processPdfOcr(
  OcrArgs args, {
  required Uint8List inputBytes,
  required PageRecognizer recognize,
  required PageRaster renderPage,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  // 0. Probe PDF.
  int pageCount;
  try {
    final probe = PdfDocument(inputBytes: inputBytes);
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
  final allExtractedBuf = StringBuffer();
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

      // 2. Preprocess raster if requested for optimal ML Kit recognition.
      final Uint8List bytesForOcr;
      if (args.enhanceImage) {
        bytesForOcr = _tryEnhanceImageBytes(imageBytes);
      } else {
        bytesForOcr = imageBytes;
      }

      // 3. Recognize.
      final elements = await recognize(bytesForOcr);
      if (elements.isNotEmpty) anyText = true;

      // 4. Output page: image + alpha-0 invisible text layer.
      final section = sections.add();
      if (wPt > hPt) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      }
      section.pageSettings.size = Size(wPt, hPt);
      final page = section.pages.add();
      page.graphics.drawImage(PdfBitmap(imageBytes), Rect.fromLTWH(0, 0, wPt, hPt));

      if (elements.isNotEmpty) {
        _drawInvisibleTextLayer(page, elements);
      }

      final pageText = formatOcrText(elements, preserveLayout: args.preserveLayout);

      textBuf.writeln('--- Page $pageNumber ---');
      textBuf.writeln(
          elements.isEmpty ? '[No text found on this page]' : pageText);

      if (elements.isNotEmpty) {
        if (allExtractedBuf.isNotEmpty) allExtractedBuf.write('\n\n');
        allExtractedBuf.write(pageText);
      }

      done++;
    }

    final pdfOut = Uint8List.fromList(outDoc.saveSync());
    final fullText = allExtractedBuf.toString();

    // 5. Outputs (unique, never overwrite).
    final pdfPath = uniqueDestination(args.outputDir, '$stem ocr.pdf');
    File(pdfPath).writeAsBytesSync(pdfOut, flush: true);
    final textPath = uniqueDestination(args.outputDir, '$stem ocr.txt');
    final textFileBytes = Uint8List.fromList(textBuf.toString().codeUnits);
    File(textPath).writeAsBytesSync(textFileBytes, flush: true);

    return OcrResult(
      outputPath: pdfPath,
      outputBytes: pdfOut.length,
      textPath: textPath,
      textBytes: textFileBytes.length,
      pageCount: selection.length,
      noText: !anyText,
      extractedText: fullText,
      wordCount: _countWords(fullText),
      characterCount: fullText.length,
    );
  } finally {
    outDoc.dispose();
  }
}

Future<OcrResult> _processImageOcr(
  OcrArgs args, {
  required Uint8List imageBytes,
  required PageRecognizer recognize,
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() ?? false) throw const JobCancelled();
  onProgress?.call(0.1, 'Analyzing image...');

  // 1. Decode image to determine dimensions & validate format.
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) {
    throw CorruptedFile(fileName: args.inputPath, detail: 'unsupported image');
  }

  // 2. Preprocess image for OCR if enabled.
  onProgress?.call(0.3, 'Enhancing image for text recognition...');
  final Uint8List bytesForOcr;
  if (args.enhanceImage) {
    bytesForOcr = _tryEnhanceImageBytes(imageBytes);
  } else {
    bytesForOcr = imageBytes;
  }

  // 3. Recognize text elements.
  onProgress?.call(0.6, 'Recognizing text...');
  final elements = await recognize(bytesForOcr);
  final anyText = elements.isNotEmpty;

  // 4. Construct Dual-Layer Searchable PDF.
  onProgress?.call(0.85, 'Generating searchable PDF...');
  final stem = _stemOf(args.inputPath);
  final outDoc = PdfDocument();
  final textBuf = StringBuffer();

  try {
    final wPt = decoded.width / _renderScale;
    final hPt = decoded.height / _renderScale;

    final section = outDoc.sections!.add();
    if (wPt > hPt) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    }
    section.pageSettings.size = Size(wPt, hPt);
    final page = section.pages.add();

    // Visual image base layer.
    page.graphics.drawImage(PdfBitmap(imageBytes), Rect.fromLTWH(0, 0, wPt, hPt));

    // Invisible text layer.
    if (elements.isNotEmpty) {
      _drawInvisibleTextLayer(page, elements);
    }

    final pageText = formatOcrText(elements, preserveLayout: args.preserveLayout);

    textBuf.writeln('--- Page 1 ---');
    textBuf.writeln(
        elements.isEmpty ? '[No text found on this page]' : pageText);

    final pdfOut = Uint8List.fromList(outDoc.saveSync());
    final fullText = elements.isEmpty ? '' : pageText;

    // 5. Outputs.
    final pdfPath = uniqueDestination(args.outputDir, '$stem ocr.pdf');
    File(pdfPath).writeAsBytesSync(pdfOut, flush: true);
    final textPath = uniqueDestination(args.outputDir, '$stem ocr.txt');
    final textFileBytes = Uint8List.fromList(textBuf.toString().codeUnits);
    File(textPath).writeAsBytesSync(textFileBytes, flush: true);

    onProgress?.call(1.0, 'Complete');

    return OcrResult(
      outputPath: pdfPath,
      outputBytes: pdfOut.length,
      textPath: textPath,
      textBytes: textFileBytes.length,
      pageCount: 1,
      noText: !anyText,
      extractedText: fullText,
      wordCount: _countWords(fullText),
      characterCount: fullText.length,
    );
  } finally {
    outDoc.dispose();
  }
}

void _drawInvisibleTextLayer(PdfPage page, List<OcrElement> elements) {
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

Uint8List _tryEnhanceImageBytes(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;
    final enhanced = enhanceDocument(decoded, preserveColor: false);
    return Uint8List.fromList(img.encodePng(enhanced));
  } catch (_) {
    return rawBytes;
  }
}

bool _isPdfBytes(Uint8List bytes) {
  if (bytes.length < 4) return false;
  return bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F
}

/// Formats OCR elements into clean, readable text preserving natural paragraph
/// breaks and left-to-right reading order.
String formatOcrText(List<OcrElement> elements, {bool preserveLayout = true}) {
  if (elements.isEmpty) return '';
  if (!preserveLayout) {
    return elements.map((e) => e.text).join(' ');
  }

  // 1. Group by logical block if provided by ML Kit.
  final hasMultipleBlocks = elements.any((e) => e.blockIndex > 0);
  if (hasMultipleBlocks) {
    final blockMap = <int, List<OcrElement>>{};
    for (final e in elements) {
      blockMap.putIfAbsent(e.blockIndex, () => []).add(e);
    }

    // Sort blocks top-to-bottom, left-to-right (handles multi-column layout).
    final sortedBlocks = blockMap.values.toList()
      ..sort((a, b) {
        final boxA = _boundsOf(a);
        final boxB = _boundsOf(b);
        final verticalOverlap = (boxA.bottom > boxB.top && boxA.top < boxB.bottom);
        if (verticalOverlap && (boxA.left - boxB.left).abs() > 40) {
          return boxA.left.compareTo(boxB.left);
        }
        return boxA.top.compareTo(boxB.top);
      });

    final blockStrings = <String>[];
    for (final block in sortedBlocks) {
      final lines = _groupIntoLines(block);
      if (lines.isNotEmpty) {
        blockStrings.add(lines.join('\n'));
      }
    }
    return blockStrings.join('\n\n');
  }

  // 2. Spatial layout analysis when block indices are flat.
  final lines = _groupIntoLines(elements);
  return lines.join('\n');
}

class _LineGroup {
  _LineGroup(this.initial) : elements = [initial];
  final OcrElement initial;
  final List<OcrElement> elements;

  double get top => elements.map((e) => e.box.top).reduce((a, b) => a < b ? a : b);
  double get bottom => elements.map((e) => e.box.bottom).reduce((a, b) => a > b ? a : b);

  bool belongs(OcrElement elem) {
    final elemH = elem.box.height > 0 ? elem.box.height : 14.0;
    final lineMid = (top + bottom) / 2.0;
    final elemMid = (elem.box.top + elem.box.bottom) / 2.0;
    return (lineMid - elemMid).abs() < (elemH * 0.65);
  }

  String render() {
    final sorted = List<OcrElement>.from(elements)
      ..sort((a, b) => a.box.left.compareTo(b.box.left));
    return sorted.map((e) => e.text).join(' ');
  }
}

List<String> _groupIntoLines(List<OcrElement> elements) {
  if (elements.isEmpty) return const [];
  final sorted = List<OcrElement>.from(elements)
    ..sort((a, b) => a.box.top.compareTo(b.box.top));

  final lines = <_LineGroup>[];
  for (final elem in sorted) {
    var placed = false;
    for (final line in lines) {
      if (line.belongs(elem)) {
        line.elements.add(elem);
        placed = true;
        break;
      }
    }
    if (!placed) {
      lines.add(_LineGroup(elem));
    }
  }

  lines.sort((a, b) => a.top.compareTo(b.top));
  return lines.map((l) => l.render()).toList();
}

Rect _boundsOf(List<OcrElement> elements) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final e in elements) {
    if (e.box.left < minX) minX = e.box.left;
    if (e.box.top < minY) minY = e.box.top;
    if (e.box.right > maxX) maxX = e.box.right;
    if (e.box.bottom > maxY) maxY = e.box.bottom;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

int _countWords(String text) {
  if (text.trim().isEmpty) return 0;
  return text.trim().split(RegExp(r'\s+')).length;
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

