import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/pdf_to_images_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List makePdf({required int pages}) {
  final doc = PdfDocument();
  doc.pageSettings.size = const Size(612, 792);
  for (var i = 0; i < pages; i++) {
    doc.pages.add();
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  late Directory tempOut;
  late String pdfPath;
  late Directory tempIn;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_p2i_out');
    tempIn = Directory.systemTemp.createTempSync('pf_p2i_in');
    pdfPath = '${tempIn.path}${Platform.pathSeparator}doc.pdf';
    File(pdfPath).writeAsBytesSync(makePdf(pages: 4));
  });

  tearDown(() {
    tempIn.deleteSync(recursive: true);
    tempOut.deleteSync(recursive: true);
  });

  /// Stub renderer: records page numbers and returns tagged fake bytes.
  (PageRenderer, List<int>) stub() {
    final calls = <int>[];
    Future<(double, double, Uint8List)> renderer(
      String inputPath,
      int pageNumber,
      int renderWidthPx,
      int renderHeightPx,
      PdfToImagesFormat format,
      int dpi,
    ) async {
      calls.add(pageNumber);
      final wPt = 612 * dpi / 72;
      final hPt = 792 * dpi / 72;
      expect(renderWidthPx, closeTo(wPt, 1));
      expect(renderHeightPx, closeTo(hPt, 1));
      return (612.0, 792.0, Uint8List.fromList('fake-image-p$pageNumber'.codeUnits));
    }

    return (renderer, calls);
  }

  test('empty selection renders every page in order', () async {
    final (renderer, calls) = stub();
    final result = await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: [],
        format: PdfToImagesFormat.png,
        dpi: 72,
      ),
      renderer: renderer,
    );

    expect(calls, [1, 2, 3, 4]);
    expect(result.imageCount, 4);
    expect(result.pageCountTotal, 4);
    expect(result.outputPath.toLowerCase().endsWith('.zip'), isTrue);
  });

  test('selection is deduplicated, clamped and sorted', () async {
    final (renderer, calls) = stub();
    await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: const [3, 99, 1, 3],
        format: PdfToImagesFormat.png,
        dpi: 72,
      ),
      renderer: renderer,
    );

    expect(calls, [1, 3]);
  });

  test('DPI scales the render size (144 → 2× page points)', () async {
    final (renderer, calls) = stub();
    await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: const [1],
        format: PdfToImagesFormat.jpeg,
        dpi: 144,
      ),
      renderer: renderer,
    );

    expect(calls, [1]); // stub itself asserts 1224 × 1584 px
  });

  test('single page → one image file, not a zip', () async {
    final (renderer, _) = stub();
    final result = await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: const [2],
        format: PdfToImagesFormat.png,
        dpi: 72,
      ),
      renderer: renderer,
    );

    expect(result.imageCount, 1);
    final name = result.outputPath.split(Platform.pathSeparator).last;
    expect(name, 'doc p2.png');
  });

  test('multi-page → zip with per-page names inside', () async {
    final (renderer, _) = stub();
    final result = await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: const [1, 3],
        format: PdfToImagesFormat.jpeg,
        dpi: 72,
      ),
      renderer: renderer,
    );

    final zip = ZipDecoder().decodeBytes(File(result.outputPath).readAsBytesSync());
    final names = zip.map((f) => f.name).toList();
    expect(names, containsAll(['doc p1.jpg', 'doc p3.jpg']));
    expect(
      String.fromCharCodes(zip.firstWhere((f) => f.name == 'doc p3.jpg').content as List<int>),
      'fake-image-p3',
    );
  });

  test('encrypted PDF → typed error (pdfx cannot open on Android)', () async {
    final encDoc = PdfDocument();
    encDoc.pages.add();
    encDoc.security.userPassword = 'pp';
    final encPath = '${tempIn.path}${Platform.pathSeparator}locked.pdf';
    File(encPath).writeAsBytesSync(Uint8List.fromList(encDoc.saveSync()));
    encDoc.dispose();

    final (renderer, _) = stub();
    await expectLater(
      pdfToImagesTask(
        PdfToImagesArgs(
          inputPath: encPath,
          outputDir: tempOut.path,
          pages: const [1],
          format: PdfToImagesFormat.png,
          dpi: 72,
        ),
        renderer: renderer,
      ),
      throwsA(isA<PureError>()),
    );
  });

  test('corrupt PDF → CorruptedFile', () async {
    final junk = '${tempIn.path}${Platform.pathSeparator}junk.pdf';
    File(junk).writeAsBytesSync(List.filled(300, 0x3C));

    final (renderer, _) = stub();
    await expectLater(
      pdfToImagesTask(
        PdfToImagesArgs(
          inputPath: junk,
          outputDir: tempOut.path,
          pages: const [1],
          format: PdfToImagesFormat.png,
          dpi: 72,
        ),
        renderer: renderer,
      ),
      throwsA(isA<CorruptedFile>()),
    );
  });

  test('all-selected-pages-out-of-range → typed error, no output', () async {
    final (renderer, _) = stub();
    await expectLater(
      pdfToImagesTask(
        PdfToImagesArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          pages: const [50, 99],
          format: PdfToImagesFormat.png,
          dpi: 72,
        ),
        renderer: renderer,
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before rendering (edge #50)', () async {
    final (renderer, calls) = stub();
    await expectLater(
      pdfToImagesTask(
        PdfToImagesArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          pages: const [1, 2],
          format: PdfToImagesFormat.png,
          dpi: 72,
        ),
        renderer: renderer,
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(calls, isEmpty);
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: source PDF untouched (F7)', () async {
    final before = File(pdfPath).readAsBytesSync();
    final (renderer, _) = stub();
    await pdfToImagesTask(
      PdfToImagesArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        pages: const [1, 2],
        format: PdfToImagesFormat.png,
        dpi: 72,
      ),
      renderer: renderer,
    );
    expect(File(pdfPath).readAsBytesSync(), before);
  });

  test('outputs never overwrite earlier results', () async {
    final (renderer, _) = stub();
    final args = PdfToImagesArgs(
      inputPath: pdfPath,
      outputDir: tempOut.path,
      pages: const [1],
      format: PdfToImagesFormat.png,
      dpi: 72,
    );
    final r1 = await pdfToImagesTask(args, renderer: renderer);
    final r2 = await pdfToImagesTask(args, renderer: renderer);
    expect(r1.outputPath == r2.outputPath, isFalse);
  });
}
