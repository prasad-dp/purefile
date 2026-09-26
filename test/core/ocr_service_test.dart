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

}
