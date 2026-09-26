import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/pdf_stamp_service.dart';
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

Uint8List makePng({int w = 200, int h = 80, int alpha = 255}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(10, 10, 10, alpha));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pf_stamp'));
  tearDown(() => temp.deleteSync(recursive: true));

  String writePdf(String name, Uint8List bytes) {
    final p = '${temp.path}${Platform.pathSeparator}$name';
    File(p).writeAsBytesSync(bytes);
    return p;
  }

  // ----------------------------------------------------------- placement

  group('stampRect math', () {
    const page = Size(595, 842);
    const stamp = Size(200, 80); // 2.5:1 aspect
    const m = 24.0;

    test('bottomRight hugs the bottom-right corner', () {
      final r = stampRect(
        pageSize: page,
        stampSize: stamp,
        anchor: StampAnchor.bottomRight,
        marginPt: m,
        scalePercent: 30,
      );
      expect(r.right, closeTo(595 - m, 0.01));
      expect(r.bottom, closeTo(842 - m, 0.01));
      expect(r.width, closeTo(595 * 0.3, 0.01));
      // Aspect preserved: h = w * (80/200)
      expect(r.height, closeTo(595 * 0.3 * 80 / 200, 0.01));
    });

    test('topLeft hugs the top-left corner', () {
      final r = stampRect(
        pageSize: page,
        stampSize: stamp,
        anchor: StampAnchor.topLeft,
        marginPt: m,
        scalePercent: 30,
      );
      expect(r.left, m);
      expect(r.top, m);
    });

    test('center centers with margin respected', () {
      final r = stampRect(
        pageSize: page,
        stampSize: stamp,
        anchor: StampAnchor.center,
        marginPt: m,
        scalePercent: 30,
      );
      expect(r.left, closeTo((595 - m - r.width) / 2, 0.01));
      expect(r.top, closeTo((842 - m - r.height) / 2, 0.01));
    });

    test('scale clamps to 5..80 percent', () {
      final tiny = stampRect(
        pageSize: page,
        stampSize: stamp,
        anchor: StampAnchor.bottomRight,
        marginPt: m,
        scalePercent: 1,
      );
      expect(tiny.width, closeTo(595 * 0.05, 0.01));
      final huge = stampRect(
        pageSize: page,
        stampSize: stamp,
        anchor: StampAnchor.bottomRight,
        marginPt: m,
        scalePercent: 99,
      );
      expect(huge.width, closeTo(595 * 0.8, 0.01));
    });
  });

  // ------------------------------------------------------------- flatten

  test('stamp flattens onto the chosen page and preserves content', () async {
    final pdfPath = writePdf('contract.pdf', makePdf(pages: 3));
    final result = await stampTask(
      StampArgs(
        inputPath: pdfPath,
        outputDir: temp.path,
        stampBytes: makePng(),
        pageNumber: 2,
        anchor: StampAnchor.bottomRight,
        scalePercent: 25,
      ),
    );

    expect(File(result.outputPath).existsSync(), isTrue);
    expect(result.pageCount, 3);

    // Original text still there (template preserved it) — read page 2 text.
    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages.count, 3);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('PureFile fixture page 0'));
    expect(text, contains('PureFile fixture page 2'));
  });

  test('ORIGINALS SACRED: input bytes untouched', () async {
    final pdfPath = writePdf('orig.pdf', makePdf(pages: 1));
    final before = File(pdfPath).readAsBytesSync();
    await stampTask(
      StampArgs(
        inputPath: pdfPath,
        outputDir: temp.path,
        stampBytes: makePng(),
      ),
    );
    expect(File(pdfPath).readAsBytesSync(), before);
  });

  test('encrypted input → PasswordRequired', () async {
    final pdfPath = writePdf('enc.pdf', makePdf(encrypt: true));
    await expectLater(
      stampTask(
        StampArgs(inputPath: pdfPath, outputDir: temp.path, stampBytes: makePng()),
      ),
      throwsA(isA<PasswordRequired>()),
    );
  });

  test('out-of-range page → UnsupportedFormat, nothing written', () async {
    final pdfPath = writePdf('oob.pdf', makePdf(pages: 2));
    final before = temp.listSync().length;
    await expectLater(
      stampTask(
        StampArgs(
          inputPath: pdfPath,
          outputDir: temp.path,
          stampBytes: makePng(),
          pageNumber: 9,
        ),
      ),
      throwsA(isA<UnsupportedFormat>()),
    );
    expect(temp.listSync().length, before);
  });

  test('unreadable stamp bytes → UnsupportedFormat', () async {
    final pdfPath = writePdf('x.pdf', makePdf(pages: 1));
    await expectLater(
      stampTask(
        StampArgs(
          inputPath: pdfPath,
          outputDir: temp.path,
          stampBytes: Uint8List(0),
        ),
      ),
      throwsA(isA<UnsupportedFormat>()),
    );
  });

  test('cancel before save → JobCancelled, nothing written', () async {
    final pdfPath = writePdf('c.pdf', makePdf(pages: 1));
    final before = temp.listSync().length;
    await expectLater(
      stampTask(
        StampArgs(inputPath: pdfPath, outputDir: temp.path, stampBytes: makePng()),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(temp.listSync().length, before);
  });

  test('rerun does not overwrite earlier output', () async {
    final pdfPath = writePdf('again.pdf', makePdf(pages: 1));
    final r1 = await stampTask(
      StampArgs(inputPath: pdfPath, outputDir: temp.path, stampBytes: makePng()),
    );
    final r2 = await stampTask(
      StampArgs(inputPath: pdfPath, outputDir: temp.path, stampBytes: makePng()),
    );
    expect(r1.outputPath != r2.outputPath, isTrue);
  });
}
