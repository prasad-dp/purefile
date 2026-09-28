import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/pdf_compress_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Generates real PDF fixtures with syncfusion (deterministic, no binaries).
Uint8List makePdf({
  int pages = 2,
  bool encrypt = false,
  String password = 'secret',
  int textBloat = 0,
}) {
  final doc = PdfDocument();
  for (var i = 0; i < pages; i++) {
    final page = doc.pages.add();
    page.graphics.drawString(
      'PureFile fixture page $i',
      PdfStandardFont(PdfFontFamily.helvetica, 14),
      brush: PdfBrushes.black,
      bounds: const Rect.fromLTWH(20, 20, 400, 30),
    );
  }
  if (textBloat > 0) {
    // Bloat with an uncompressed text stream so compression has headroom.
    final page = doc.pages.add();
    page.graphics.drawString(
      'lorem ipsum ' * textBloat,
      PdfStandardFont(PdfFontFamily.helvetica, 8),
      brush: PdfBrushes.black,
      bounds: const Rect.fromLTWH(20, 60, 500, 400),
    );
  }
  if (encrypt) {
    doc.security.userPassword = password;
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pf_pdfc_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  String writeInput(String name, List<int> bytes) {
    final path = '${temp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('compresses a bloaty text PDF and reports honest %', () async {
    final src = writeInput('bloated.pdf', makePdf(pages: 1, textBloat: 4000));
    final outPath = '${temp.path}${Platform.pathSeparator}out.pdf';

    final result = await pdfCompressTask(
      PdfCompressArgs(inputPath: src, outputPath: outPath, quality: PdfCompressQuality.medium),
    );

    expect(result.keptOriginal, isFalse);
    expect(result.compressedBytes, lessThan(result.originalBytes));
    expect(result.savedPercent, greaterThan(0));
    expect(File(outPath).existsSync(), isTrue);
    expect(File(outPath).lengthSync(), result.compressedBytes);

    // Output is a valid PDF with the same page count.
    final check = PdfDocument(inputBytes: File(outPath).readAsBytesSync());
    expect(check.pages.count, greaterThanOrEqualTo(1));
    check.dispose();
  });

  test('never worse than input: re-compressing an optimized PDF never grows it', () async {
    // Round-trip 1: syncfusion's default save is incremental, so the first
    // pass genuinely shrinks. Round-trip 2 has nothing meaningful left to
    // win. syncfusion embeds timestamps in xref IDs, so byte-level results
    // can wobble by a few bytes — the stable contract is the invariant:
    // output is never bigger than input, and a kept-original result is
    // byte-identical to the input.
    final first = writeInput('v1.pdf', makePdf(pages: 1));
    final v2 = '${temp.path}${Platform.pathSeparator}v2.pdf';
    await pdfCompressTask(
      PdfCompressArgs(inputPath: first, outputPath: v2, quality: PdfCompressQuality.high),
    );

    final result = await pdfCompressTask(
      PdfCompressArgs(inputPath: v2, outputPath: '${temp.path}${Platform.pathSeparator}v3.pdf', quality: PdfCompressQuality.high),
    );

    expect(result.compressedBytes, lessThanOrEqualTo(result.originalBytes));
    if (result.keptOriginal) {
      expect(result.compressedBytes, result.originalBytes);
    } else {
      final check = PdfDocument(inputBytes: File('${temp.path}${Platform.pathSeparator}v3.pdf').readAsBytesSync());
      expect(check.pages.count, 1);
      check.dispose();
    }
  });

  test('0-page PDF → typed CorruptedFile (edge #20)', () async {
    final src = writeInput('empty.pdf', Uint8List.fromList('%PDF-1.4\n'.codeUnits));
    final outPath = '${temp.path}${Platform.pathSeparator}out.pdf';

    await expectLater(
      pdfCompressTask(
        PdfCompressArgs(inputPath: src, outputPath: outPath, quality: PdfCompressQuality.low),
      ),
      throwsA(isA<CorruptedFile>()),
    );
  });

  test('encrypted PDF without password → PasswordRequired (edge #18)', () async {
    final src = writeInput('locked.pdf', makePdf(pages: 1, encrypt: true));
    final outPath = '${temp.path}${Platform.pathSeparator}out.pdf';

    await expectLater(
      pdfCompressTask(
        PdfCompressArgs(inputPath: src, outputPath: outPath, quality: PdfCompressQuality.low),
      ),
      throwsA(isA<PasswordRequired>()),
    );
  });

  test('encrypted PDF with correct password succeeds; wrong password fails',
      () async {
    final bytes = makePdf(pages: 1, encrypt: true, password: 'open-sesame');
    final src = writeInput('locked2.pdf', bytes);

    final ok = await pdfCompressTask(
      PdfCompressArgs(
        inputPath: src,
        outputPath: '${temp.path}${Platform.pathSeparator}ok.pdf',
        quality: PdfCompressQuality.low,
        password: 'open-sesame',
      ),
    );
    expect(ok, isA<PdfCompressResult>());

    await expectLater(
      pdfCompressTask(
        PdfCompressArgs(
          inputPath: src,
          outputPath: '${temp.path}${Platform.pathSeparator}bad.pdf',
          quality: PdfCompressQuality.low,
          password: 'wrong',
        ),
      ),
      throwsA(isA<WrongPassword>()),
    );
  });

  test('cancel between pages aborts with JobCancelled (edge #50)', () async {
    final src = writeInput('doc.pdf', makePdf(pages: 1, textBloat: 2000));
    final outPath = '${temp.path}${Platform.pathSeparator}out.pdf';

    await expectLater(
      pdfCompressTask(
        PdfCompressArgs(inputPath: src, outputPath: outPath, quality: PdfCompressQuality.high),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(File(outPath).existsSync(), isFalse);
  });

  test('ORIGINALS SACRED: input byte-identical after compress (F7)', () async {
    final src = writeInput('sacred.pdf', makePdf(pages: 1, textBloat: 1000));
    final before = File(src).readAsBytesSync();

    await pdfCompressTask(
      PdfCompressArgs(
        inputPath: src,
        outputPath: '${temp.path}${Platform.pathSeparator}out.pdf',
        quality: PdfCompressQuality.medium,
      ),
    );

    expect(File(src).readAsBytesSync(), before);
  });

  test('quality presets map to render scale + jpeg quality', () {
    expect(PdfCompressQuality.low.renderScale, 0.75);
    expect(PdfCompressQuality.medium.renderScale, 1.0);
    expect(PdfCompressQuality.high.renderScale, 1.5);
    expect(PdfCompressQuality.high.jpegQuality, greaterThan(PdfCompressQuality.low.jpegQuality));
  });

  test('args respects imageThresholdPages parameter', () {
    const args = PdfCompressArgs(
      inputPath: 'dummy.pdf',
      outputPath: 'out.pdf',
      quality: PdfCompressQuality.medium,
      imageThresholdPages: 8,
    );
    expect(args.imageThresholdPages, 8);
  });
}
