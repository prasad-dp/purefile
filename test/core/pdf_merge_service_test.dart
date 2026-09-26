import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/pdf_merge_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List makePdf({required int pages, required double widthPt, required double heightPt}) {
  final doc = PdfDocument();
  doc.pageSettings.size = Size(widthPt, heightPt);
  for (var i = 0; i < pages; i++) {
    final page = doc.pages.add();
    page.graphics.drawString(
      'Merge fixture p$i',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      brush: PdfBrushes.black,
      bounds: const Rect.fromLTWH(20, 20, 300, 20),
    );
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

Uint8List makePng({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 220, 240));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tempIn;
  late Directory tempOut;

  setUp(() {
    tempIn = Directory.systemTemp.createTempSync('pf_merge_in');
    tempOut = Directory.systemTemp.createTempSync('pf_merge_out');
  });

  tearDown(() {
    tempIn.deleteSync(recursive: true);
    tempOut.deleteSync(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final path = '${tempIn.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('merges two PDFs in order — page count and sizes verified', () async {
    final a = write('a.pdf', makePdf(pages: 2, widthPt: 612, heightPt: 792));
    final b = write('b.pdf', makePdf(pages: 3, widthPt: 595, heightPt: 842));

    final result = await pdfMergeTask(
      MergeArgs(
        items: [
          MergeItem(path: a, name: 'a.pdf', isPdf: true),
          MergeItem(path: b, name: 'b.pdf', isPdf: true),
        ],
        outputDir: tempOut.path,
      ),
    );

    expect(result.failedNames, isEmpty);
    final merged = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(merged.pages.count, 5);
    // Order check: pages 1–2 are letter-sized (from a.pdf), 3–5 are A4.
    expect(merged.pages[0].size.width, closeTo(612, 1));
    expect(merged.pages[2].size.width, closeTo(595, 1));
    merged.dispose();
  });

  test('merges PDF + image mix; image becomes a page (F10 mixed inputs)', () async {
    final a = write('doc.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));
    final p = write('photo.png', makePng(width: 800, height: 600));

    final result = await pdfMergeTask(
      MergeArgs(
        items: [
          MergeItem(path: a, name: 'doc.pdf', isPdf: true),
          MergeItem(path: p, name: 'photo.png', isPdf: false),
        ],
        outputDir: tempOut.path,
      ),
    );

    expect(result.failedNames, isEmpty);
    final merged = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(merged.pages.count, 2);
    // Page 2 keeps the image's pixel dimensions as its page size.
    expect(merged.pages[1].size.width, closeTo(800, 1));
    expect(merged.pages[1].size.height, closeTo(600, 1));
    merged.dispose();
  });

  test('duplicate input names merge fine — outputs auto-named (edge #31 spirit)', () async {
    final a = write('doc1.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));
    final b = write('doc2.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));

    final result1 = await pdfMergeTask(
      MergeArgs(
        items: [MergeItem(path: a, name: 'same.pdf', isPdf: true)],
        outputDir: tempOut.path,
      ),
    );
    final result2 = await pdfMergeTask(
      MergeArgs(
        items: [MergeItem(path: b, name: 'same.pdf', isPdf: true)],
        outputDir: tempOut.path,
      ),
    );

    // uniqueDestination prevents overwrite across runs.
    expect(result1.outputPath == result2.outputPath, isFalse);
  });

  test('encrypted item without password fails the whole merge with PasswordRequired', () async {
    final encDoc = PdfDocument();
    encDoc.pages.add();
    encDoc.security.userPassword = 'x';
    final encBytes = encDoc.saveSync();
    encDoc.dispose();
    final e = write('locked.pdf', encBytes);
    final ok = write('ok.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));

    // Only the encrypted item → mergedCount 0 → first error surfaces.
    await expectLater(
      pdfMergeTask(
        MergeArgs(
          items: [MergeItem(path: e, name: 'locked.pdf', isPdf: true)],
          outputDir: tempOut.path,
        ),
      ),
      throwsA(isA<PureError>()),
    );

    // Mixed: encrypted + good item, no password → PasswordRequired surfaces.
    await expectLater(
      pdfMergeTask(
        MergeArgs(
          items: [
            MergeItem(path: e, name: 'locked.pdf', isPdf: true),
            MergeItem(path: ok, name: 'ok.pdf', isPdf: true),
          ],
          outputDir: tempOut.path,
        ),
      ),
      throwsA(isA<PasswordRequired>()),
    );
  });

  test('encrypted item WITH correct password merges successfully', () async {
    final encDoc = PdfDocument();
    encDoc.pages.add();
    encDoc.security.userPassword = 'pass';
    final encBytes = encDoc.saveSync();
    encDoc.dispose();
    final e = write('locked.pdf', encBytes);

    final result = await pdfMergeTask(
      MergeArgs(
        items: [MergeItem(path: e, name: 'locked.pdf', isPdf: true)],
        outputDir: tempOut.path,
        password: 'pass',
      ),
    );
    expect(result.failedNames, isEmpty);
    final merged = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(merged.pages.count, 1);
    merged.dispose();
  });

  test('corrupt PDF item is failed, good items still merge (partial success)',
      () async {
    final junk = write('junk.pdf', List.filled(500, 0xAB));
    final ok = write('ok.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));

    final result = await pdfMergeTask(
      MergeArgs(
        items: [
          MergeItem(path: junk, name: 'junk.pdf', isPdf: true),
          MergeItem(path: ok, name: 'ok.pdf', isPdf: true),
        ],
        outputDir: tempOut.path,
      ),
    );

    expect(result.failedNames, contains('junk.pdf'));
    expect(result.failedNames, isNot(contains('ok.pdf')));
    final merged = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(merged.pages.count, 1);
    merged.dispose();
  });

  test('all items fail → typed error, no output file', () async {
    final junk1 = write('junk1.pdf', List.filled(300, 1));
    final junk2 = write('junk2.pdf', List.filled(300, 2));

    await expectLater(
      pdfMergeTask(
        MergeArgs(
          items: [
            MergeItem(path: junk1, name: 'junk1.pdf', isPdf: true),
            MergeItem(path: junk2, name: 'junk2.pdf', isPdf: true),
          ],
          outputDir: tempOut.path,
        ),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before any work (edge #50)', () async {
    final a = write('a.pdf', makePdf(pages: 1, widthPt: 612, heightPt: 792));

    await expectLater(
      pdfMergeTask(
        MergeArgs(
          items: [MergeItem(path: a, name: 'a.pdf', isPdf: true)],
          outputDir: tempOut.path,
        ),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
  });

  test('ORIGINALS SACRED: inputs byte-identical after merge (F7)', () async {
    final a = write('a.pdf', makePdf(pages: 2, widthPt: 612, heightPt: 792));
    final p = write('p.png', makePng(width: 300, height: 300));
    final beforeA = File(a).readAsBytesSync();
    final beforeP = File(p).readAsBytesSync();

    await pdfMergeTask(
      MergeArgs(
        items: [
          MergeItem(path: a, name: 'a.pdf', isPdf: true),
          MergeItem(path: p, name: 'p.png', isPdf: false),
        ],
        outputDir: tempOut.path,
      ),
    );

    expect(File(a).readAsBytesSync(), beforeA);
    expect(File(p).readAsBytesSync(), beforeP);
  });
}
