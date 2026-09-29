import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List makePdf({int pages = 2, bool encrypt = false}) {
  final doc = PdfDocument();
  for (var i = 0; i < pages; i++) {
    final page = doc.pages.add();
    page.graphics.drawString(
      'PureFile fixture page $i',
      PdfStandardFont(PdfFontFamily.helvetica, 14),
      brush: PdfBrushes.black,
      bounds: Rect.fromLTWH(50, 50.0 + 30 * i, 300, 20),
    );
  }
  if (encrypt) {
    doc.security.userPassword = 'secret';
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pf_ocr'));
  tearDown(() => temp.deleteSync(recursive: true));

  String writePdf(String name, Uint8List bytes) {
    final p = '${temp.path}${Platform.pathSeparator}$name';
    File(p).writeAsBytesSync(bytes);
    return p;
  }

  /// Synthetic raster (pdfx needs platform channels, unavailable in unit
  /// tests): a white PNG sized like A4 at 200/72 scale.
  PageRaster fakeRaster() {
    return (inputPath, pageNumber) async {
      // Page is 595x842 pt (A4); render "at 200 DPI".
      const scale = 200 / 72;
      final w = (595 * scale).round();
      final h = (842 * scale).round();
      final image = img.Image(width: w, height: h, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      return (595.0, 842.0, Uint8List.fromList(img.encodePng(image)));
    };
  }

  test('OCR produces a searchable PDF: invisible text is extractable', () async {
    final pdfPath = writePdf('report.pdf', makePdf(pages: 1));
    OcrElement elem(String text) => OcrElement(
          text: text,
          box: Rect.fromLTWH(50 * 200 / 72, 100 * 200 / 72, 300 * 200 / 72, 16),
        );

    final result = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path),
      recognize: (_) async => [elem('searchable'), elem('ocr layer')],
      renderPage: fakeRaster(),
    );

    expect(File(result.outputPath).existsSync(), isTrue);
    expect(File(result.textPath).existsSync(), isTrue);
    expect(result.pageCount, 1);
    expect(result.noText, isFalse);

    // THE searchable-PDF contract: text extraction of the output finds the
    // recognized words even though nothing visibly renders.
    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('searchable'));
    expect(text, contains('ocr layer'));
  });

  test('text companion has per-page sections', () async {
    final pdfPath = writePdf('doc.pdf', makePdf(pages: 2));
    var call = 0;
    final result = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path),
      recognize: (_) async => ++call == 1
          ? [
              OcrElement(
                text: 'line one',
                box: Rect.fromLTWH(100, 200, 400, 20),
              ),
            ]
          : const [],
      renderPage: fakeRaster(),
    );
    final txt = File(result.textPath).readAsStringSync();
    expect(txt, contains('--- Page 1 ---'));
    expect(txt, contains('--- Page 2 ---'));
    expect(txt, contains('line one'));
    expect(txt, contains('[No text found on this page]'));
  });

  test('all pages text-free sets noText (edge #25)', () async {
    final pdfPath = writePdf('blank.pdf', makePdf(pages: 1));
    final result = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path),
      recognize: (_) async => const [],
      renderPage: fakeRaster(),
    );
    expect(result.noText, isTrue);
    // Outputs still exist — the text file states the emptiness.
    expect(File(result.textPath).existsSync(), isTrue);
  });

  test('page selection narrows output pages; out-of-range clamped away', () async {
    final pdfPath = writePdf('sel.pdf', makePdf(pages: 3));
    final result = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path, pages: [2, 99]),
      recognize: (_) async => const [],
      renderPage: fakeRaster(),
    );
    expect(result.pageCount, 1);
    expect(File(result.textPath).readAsStringSync(), contains('--- Page 2 ---'));
  });

  test('entirely out-of-range selection → typed error, nothing written', () async {
    final pdfPath = writePdf('bad.pdf', makePdf(pages: 2));
    final before = temp.listSync().length;
    await expectLater(
      ocrTask(
        OcrArgs(inputPath: pdfPath, outputDir: temp.path, pages: [50]),
        recognize: (_) async => const [],
        renderPage: fakeRaster(),
      ),
      throwsA(isA<UnsupportedFormat>()),
    );
    expect(temp.listSync().length, before);
  });

  test('encrypted PDF → PasswordRequired', () async {
    final pdfPath = writePdf('enc.pdf', makePdf(encrypt: true));
    await expectLater(
      ocrTask(
        OcrArgs(inputPath: pdfPath, outputDir: temp.path),
        recognize: (_) async => const [],
        renderPage: fakeRaster(),
      ),
      throwsA(isA<PasswordRequired>()),
    );
  });

  test('corrupt PDF → CorruptedFile', () async {
    final pdfPath = writePdf('junk.pdf', Uint8List.fromList(List.filled(64, 0x11)));
    await expectLater(
      ocrTask(
        OcrArgs(inputPath: pdfPath, outputDir: temp.path),
        recognize: (_) async => const [],
        renderPage: fakeRaster(),
      ),
      throwsA(isA<CorruptedFile>()),
    );
  });

  test('cancel before first page → JobCancelled, nothing written', () async {
    final pdfPath = writePdf('c.pdf', makePdf(pages: 1));
    final before = temp.listSync().length;
    await expectLater(
      ocrTask(
        OcrArgs(inputPath: pdfPath, outputDir: temp.path),
        recognize: (_) async => const [],
        renderPage: fakeRaster(),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(temp.listSync().length, before);
  });

  test('rerun does not overwrite earlier outputs', () async {
    final pdfPath = writePdf('again.pdf', makePdf(pages: 1));
    final r1 = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path),
      recognize: (_) async => const [],
      renderPage: fakeRaster(),
    );
    final r2 = await ocrTask(
      OcrArgs(inputPath: pdfPath, outputDir: temp.path),
      recognize: (_) async => const [],
      renderPage: fakeRaster(),
    );
    expect(r1.outputPath != r2.outputPath, isTrue);
    expect(r1.textPath != r2.textPath, isTrue);
  });

  test('direct Image OCR produces searchable PDF and extracted text metrics', () async {
    // Synthetic PNG image
    final testImage = img.Image(width: 400, height: 600, numChannels: 3);
    img.fill(testImage, color: img.ColorRgb8(240, 240, 240));
    final pngPath = '${temp.path}${Platform.pathSeparator}receipt.png';
    File(pngPath).writeAsBytesSync(img.encodePng(testImage));

    final result = await ocrTask(
      OcrArgs(inputPath: pngPath, outputDir: temp.path, enhanceImage: false),
      recognize: (_) async => [
        const OcrElement(
          text: 'Receipt Total: \$42.50',
          box: Rect.fromLTWH(20, 50, 200, 25),
          blockIndex: 0,
        ),
        const OcrElement(
          text: 'Thank you for shopping',
          box: Rect.fromLTWH(20, 100, 250, 25),
          blockIndex: 1,
        ),
      ],
      renderPage: fakeRaster(),
    );

    expect(File(result.outputPath).existsSync(), isTrue);
    expect(File(result.textPath).existsSync(), isTrue);
    expect(result.pageCount, 1);
    expect(result.noText, isFalse);
    expect(result.wordCount, greaterThan(3));
    expect(result.characterCount, greaterThan(10));
    expect(result.extractedText, contains('Receipt Total: \$42.50'));
    expect(result.extractedText, contains('Thank you for shopping'));

    // Check searchable PDF extraction
    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    final pdfExtracted = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(pdfExtracted, contains('Receipt Total'));
  });

  test('multi-block layout preserves paragraphs with double newlines', () async {
    final elements = [
      const OcrElement(
        text: 'Heading Title',
        box: Rect.fromLTWH(50, 50, 200, 20),
        blockIndex: 0,
      ),
      const OcrElement(
        text: 'Paragraph body sentence one.',
        box: Rect.fromLTWH(50, 100, 300, 18),
        blockIndex: 1,
      ),
      const OcrElement(
        text: 'Paragraph body sentence two.',
        box: Rect.fromLTWH(50, 125, 300, 18),
        blockIndex: 1,
      ),
    ];

    final formatted = formatOcrText(elements, preserveLayout: true);
    expect(formatted, contains('Heading Title\n\nParagraph body sentence one.'));
    expect(formatted, contains('sentence one.\nParagraph body sentence two.'));
  });

  test('multi-image batch OCR creates single multi-page searchable PDF', () async {
    final img1 = img.Image(width: 300, height: 400, numChannels: 3);
    final img2 = img.Image(width: 300, height: 400, numChannels: 3);
    final p1 = '${temp.path}${Platform.pathSeparator}doc_p1.png';
    final p2 = '${temp.path}${Platform.pathSeparator}doc_p2.png';
    File(p1).writeAsBytesSync(img.encodePng(img1));
    File(p2).writeAsBytesSync(img.encodePng(img2));

    var callCount = 0;
    final result = await ocrTask(
      OcrArgs(
        imagePaths: [p1, p2],
        outputDir: temp.path,
        enhanceImage: false,
      ),
      recognize: (_) async => [
        OcrElement(
          text: 'Document Page ${++callCount}',
          box: const Rect.fromLTWH(20, 40, 150, 20),
          blockIndex: 0,
        ),
      ],
      renderPage: fakeRaster(),
    );

    expect(result.pageCount, 2);
    expect(File(result.outputPath).existsSync(), isTrue);
    expect(File(result.textPath).existsSync(), isTrue);
    expect(result.extractedText, contains('Document Page 1'));
    expect(result.extractedText, contains('Document Page 2'));

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages.count, 2);
    final extracted = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(extracted, contains('Document Page 1'));
    expect(extracted, contains('Document Page 2'));
  });
}

