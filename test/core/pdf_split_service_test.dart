import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/pdf_split_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List makePdf({required int pages, required double widthPt, required double heightPt}) {
  final doc = PdfDocument();
  // Per-page sections so wide pages keep their true (w,h) MediaBox —
  // document-level settings normalize portrait sizes to (min,max).
  for (var i = 0; i < pages; i++) {
    final section = doc.sections!.add();
    if (widthPt > heightPt) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    }
    section.pageSettings.size = Size(widthPt, heightPt);
    section.pages.add().graphics.drawString(
          'Split fixture page ${i + 1}',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
          brush: PdfBrushes.black,
          bounds: const Rect.fromLTWH(20, 20, 300, 20),
        );
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

List<String> pageTexts(String path) {
  final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
  try {
    return [
      for (var i = 0; i < doc.pages.count; i++)
        PdfTextExtractor(doc).extractText(startPageIndex: i, endPageIndex: i).trim(),
    ];
  } finally {
    doc.dispose();
  }
}

void main() {
  late Directory tempOut;
  late String pdfPath;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_split_out');
    pdfPath = '${Directory.systemTemp.createTempSync('pf_split_in').path}'
        '${Platform.pathSeparator}report.pdf';
    File(pdfPath).writeAsBytesSync(makePdf(pages: 6, widthPt: 612, heightPt: 792));
  });

  tearDown(() {
    tempOut.deleteSync(recursive: true);
  });

  test('everyN: 6 pages ÷ 2 → three 2-page pieces in order', () async {
    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.everyN,
        interval: 2,
      ),
    );

    expect(result.pieceCount, 3);
    // 2+ pieces → zip (edge #36).
    expect(result.outputPath.toLowerCase().endsWith('.zip'), isTrue);

    final zip = ZipDecoder().decodeBytes(File(result.outputPath).readAsBytesSync());
    expect(zip.length, 3);
    final text0 = pageTextFromZip(zip, 'report_p1-2.pdf');
    expect(text0, contains('page 1'));
    expect(text0, contains('page 2'));
    expect(text0, isNot(contains('page 3')));
    expect(pageTextFromZip(zip, 'report_p5-6.pdf'), contains('page 6'));
  });

  test('ranges: 1-3,5 keeps order and drops excluded pages', () async {
    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.ranges,
        ranges: const [(1, 3), (5, 5)],
      ),
    );

    expect(result.pieceCount, 2);
    final zip = ZipDecoder().decodeBytes(File(result.outputPath).readAsBytesSync());
    expect(pageTextFromZip(zip, 'report_p1-3.pdf'), contains('page 3'));
    expect(pageTextFromZip(zip, 'report_p1-3.pdf'), isNot(contains('page 4')));
    expect(pageTextFromZip(zip, 'report_p5.pdf'), contains('page 5'));
  });

  test('extract: selection is deduplicated and sorted', () async {
    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.extract,
        selection: const [4, 2, 2, 6],
      ),
    );

    expect(result.pieceCount, 3);
    final zip = ZipDecoder().decodeBytes(File(result.outputPath).readAsBytesSync());
    // Sorted → report_p2.pdf, report_p4.pdf, report_p6.pdf.
    expect(zip.map((f) => f.name), containsAll(['report_p2.pdf', 'report_p6.pdf']));
    expect(zip.map((f) => f.name), isNot(contains('report_p5.pdf')));
  });

  test('single-piece split produces a PDF, not a zip', () async {
    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.extract,
        selection: const [3],
      ),
    );

    expect(result.pieceCount, 1);
    expect(result.outputPath.toLowerCase().endsWith('.pdf'), isTrue);
    expect(pageTexts(result.outputPath), ['Split fixture page 3']);
  });

  test('landscape pages keep their size in pieces (F3 lesson)', () async {
    final widePath = '${Directory.systemTemp.createTempSync('pf_split_in').path}'
        '${Platform.pathSeparator}wide.pdf';
    File(widePath).writeAsBytesSync(makePdf(pages: 1, widthPt: 800, heightPt: 600));
    addTearDown(() => File(widePath).parent.deleteSync(recursive: true));

    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: widePath,
        outputDir: tempOut.path,
        mode: SplitMode.extract,
        selection: const [1],
      ),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages[0].size.width, closeTo(800, 1));
    expect(doc.pages[0].size.height, closeTo(600, 1));
    doc.dispose();
  });

  test('interval < 1 → typed error, no output', () async {
    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          mode: SplitMode.everyN,
          interval: 0,
        ),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ranges entirely outside the document → typed error (edge #44)', () async {
    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          mode: SplitMode.ranges,
          ranges: const [(99, 105)],
        ),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('partially-valid ranges keep the in-bounds piece (edge #44)', () async {
    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.ranges,
        ranges: const [(5, 9), (100, 101)],
      ),
    );

    expect(result.pieceCount, 1);
    // One piece → plain PDF output (5..9 clamps to 5..6 of the 6-page doc).
    expect(result.outputPath.toLowerCase().endsWith('.pdf'), isTrue);
    final text = pageTexts(result.outputPath).join(' ');
    expect(text, contains('page 5'));
    expect(text, contains('page 6'));
    expect(text, isNot(contains('page 4')));
  });

  test('extract with only out-of-bounds pages → typed error', () async {
    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          mode: SplitMode.extract,
          selection: const [0, 99],
        ),
      ),
      throwsA(isA<PureError>()),
    );
  });

  test('1-page PDF splits to a single copy-through-like output', () async {
    final single = '${Directory.systemTemp.createTempSync('pf_split_in').path}'
        '${Platform.pathSeparator}one.pdf';
    File(single).writeAsBytesSync(makePdf(pages: 1, widthPt: 612, heightPt: 792));
    addTearDown(() => File(single).parent.deleteSync(recursive: true));

    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: single,
        outputDir: tempOut.path,
        mode: SplitMode.everyN,
        interval: 1,
      ),
    );

    expect(result.pieceCount, 1);
    expect(File(result.outputPath).existsSync(), isTrue);
  });

  test('encrypted without password → PasswordRequired; with it → works', () async {
    final encDoc = PdfDocument();
    encDoc.pages.add();
    encDoc.security.userPassword = 'pp';
    final encPath = '${Directory.systemTemp.createTempSync('pf_split_in').path}'
        '${Platform.pathSeparator}locked.pdf';
    File(encPath).writeAsBytesSync(Uint8List.fromList(encDoc.saveSync()));
    encDoc.dispose();
    addTearDown(() => File(encPath).parent.deleteSync(recursive: true));

    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: encPath,
          outputDir: tempOut.path,
          mode: SplitMode.extract,
          selection: const [1],
        ),
      ),
      throwsA(isA<PasswordRequired>()),
    );

    final result = await pdfSplitTask(
      SplitArgs(
        inputPath: encPath,
        outputDir: tempOut.path,
        mode: SplitMode.extract,
        selection: const [1],
        password: 'pp',
      ),
    );
    expect(result.pieceCount, 1);
  });

  test('corrupt PDF → CorruptedFile, no output', () async {
    final junk = '${Directory.systemTemp.createTempSync('pf_split_in').path}'
        '${Platform.pathSeparator}junk.pdf';
    File(junk).writeAsBytesSync(List.filled(400, 0x5A));
    addTearDown(() => File(junk).parent.deleteSync(recursive: true));

    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: junk,
          outputDir: tempOut.path,
          mode: SplitMode.everyN,
          interval: 1,
        ),
      ),
      throwsA(isA<CorruptedFile>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before any piece is written (edge #50)', () async {
    await expectLater(
      pdfSplitTask(
        SplitArgs(
          inputPath: pdfPath,
          outputDir: tempOut.path,
          mode: SplitMode.everyN,
          interval: 2,
        ),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: source bytes untouched after split (F7)', () async {
    final before = File(pdfPath).readAsBytesSync();
    await pdfSplitTask(
      SplitArgs(
        inputPath: pdfPath,
        outputDir: tempOut.path,
        mode: SplitMode.everyN,
        interval: 3,
      ),
    );
    expect(File(pdfPath).readAsBytesSync(), before);
  });

  test('outputs never overwrite earlier results (duplicate name safety)', () async {
    final args = SplitArgs(
      inputPath: pdfPath,
      outputDir: tempOut.path,
      mode: SplitMode.extract,
      selection: const [1],
    );
    final r1 = await pdfSplitTask(args);
    final r2 = await pdfSplitTask(args);
    expect(r1.outputPath == r2.outputPath, isFalse);
  });
}

String pageTextFromZip(Archive zip, String name) {
  final file = zip.firstWhere((f) => f.name == name);
  final tmp = Directory.systemTemp.createTempSync('pf_split_zip');
  final path = '${tmp.path}${Platform.pathSeparator}$name';
  File(path).writeAsBytesSync(List<int>.from(file.content as List<int>));
  addTearDown(() => tmp.deleteSync(recursive: true));
  return pageTexts(path).join(' ');
}
