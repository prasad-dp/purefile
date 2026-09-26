import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/pdf/images_to_pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List makePdfSide({required double widthPt, required double heightPt}) {
  final doc = PdfDocument();
  final section = doc.sections!.add();
  section.pageSettings.orientation =
      widthPt > heightPt ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
  section.pageSettings.size = Size(widthPt, heightPt);
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

Uint8List makeJpeg({int width = 640, int height = 480, img.Image? content}) {
  final image = content ?? img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(180, 200, 230));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// Encodes a landscape JPEG with EXIF orientation 6 injected, so that a
/// correct pipeline must render it as portrait (swapped dimensions).
Uint8List makeRotatedJpeg() {
  final image = img.Image(width: 800, height: 600);
  img.fill(image, color: img.ColorRgb8(200, 120, 120));
  final jpegNoExif = img.encodeJpg(image, quality: 90);

  final exif = img.ExifData();
  exif.imageIfd.orientation = 6;
  final injected = img.injectJpgExif(jpegNoExif, exif);
  return Uint8List.fromList(injected ?? jpegNoExif);
}

void main() {
  late Directory tempOut;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_i2p_out');
  });

  tearDown(() {
    tempOut.deleteSync(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final path = '${Directory.systemTemp.createTempSync('pf_i2p_in').path}'
        '${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('creates one page per image, in the given order', () async {
    final a = write('a.jpg', makeJpeg(width: 400, height: 300));
    final b = write('b.png', Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 500))));

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(images: [(a, 'a.jpg'), (b, 'b.png')], outputDir: tempOut.path),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages.count, 2);
    expect(doc.pages[0].size.width, closeTo(400, 1)); // a.jpg first
    expect(doc.pages[1].size.height, closeTo(500, 1)); // b.png second
    doc.dispose();
  });

  test('EXIF-rotated photo renders upright (orientation baked)', () async {
    final rotated = write('photo.jpg', makeRotatedJpeg());

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(images: [(rotated, 'photo.jpg')], outputDir: tempOut.path),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    // Orientation 6: stored 800×600 must become 600×800 after baking.
    expect(doc.pages[0].size.width, closeTo(600, 1));
    expect(doc.pages[0].size.height, closeTo(800, 1));
    doc.dispose();
  });

  test('landscape image produces a landscape page (F3 lesson)', () async {
    final wide = write('wide.png', Uint8List.fromList(img.encodePng(img.Image(width: 800, height: 600))));

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(images: [(wide, 'wide.png')], outputDir: tempOut.path),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages[0].size.width, closeTo(800, 1));
    expect(doc.pages[0].size.height, closeTo(600, 1));
    doc.dispose();
  });

  test('fitA4: portrait image → portrait A4 page', () async {
    final tall = write('tall.jpg', makeJpeg(width: 400, height: 800));

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(
        images: [(tall, 'tall.jpg')],
        outputDir: tempOut.path,
        fit: ImageFit.a4,
      ),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages[0].size.width, closeTo(595, 1));
    expect(doc.pages[0].size.height, closeTo(842, 1));
    doc.dispose();
  });

  test('fitA4: wide image → landscape A4 page', () async {
    final wide = write('wide.jpg', makeJpeg(width: 800, height: 400));

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(
        images: [(wide, 'wide.jpg')],
        outputDir: tempOut.path,
        fit: ImageFit.a4,
      ),
    );

    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages[0].size.width, closeTo(842, 1));
    expect(doc.pages[0].size.height, closeTo(595, 1));
    doc.dispose();
  });

  test('corrupt image skipped, rest merged (partial success)', () async {
    final junk = write('junk.png', List.filled(200, 0x1F));
    final ok = write('ok.jpg', makeJpeg());

    final result = await imagesToPdfTask(
      ImagesToPdfArgs(
        images: [(junk, 'junk.png'), (ok, 'ok.jpg')],
        outputDir: tempOut.path,
      ),
    );

    expect(result.pageCount, 1);
    final doc = PdfDocument(inputBytes: File(result.outputPath).readAsBytesSync());
    expect(doc.pages.count, 1);
    doc.dispose();
  });

  test('all images unreadable → typed error, no output', () async {
    final junk = write('junk.png', List.filled(200, 0x2A));

    await expectLater(
      imagesToPdfTask(
        ImagesToPdfArgs(images: [(junk, 'junk.png')], outputDir: tempOut.path),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before writing (edge #50)', () async {
    final ok = write('ok.jpg', makeJpeg());

    await expectLater(
      imagesToPdfTask(
        ImagesToPdfArgs(images: [(ok, 'ok.jpg')], outputDir: tempOut.path),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: image files untouched (F7)', () async {
    final a = write('a.jpg', makeJpeg());
    final before = File(a).readAsBytesSync();

    await imagesToPdfTask(
      ImagesToPdfArgs(images: [(a, 'a.jpg')], outputDir: tempOut.path),
    );

    expect(File(a).readAsBytesSync(), before);
  });

  test('outputs never overwrite earlier results', () async {
    final a = write('a.jpg', makeJpeg());
    final args = ImagesToPdfArgs(images: [(a, 'a.jpg')], outputDir: tempOut.path);

    final r1 = await imagesToPdfTask(args);
    final r2 = await imagesToPdfTask(args);
    expect(r1.outputPath == r2.outputPath, isFalse);
  });

  test('single image names the output after itself; multi uses _plusN', () async {
    final a = write('beach.jpg', makeJpeg());
    final b = write('sunset.jpg', makeJpeg());

    final r1 = await imagesToPdfTask(
      ImagesToPdfArgs(images: [(a, 'beach.jpg')], outputDir: tempOut.path),
    );
    expect(r1.outputPath.split(Platform.pathSeparator).last, 'beach.pdf');

    final r2 = await imagesToPdfTask(
      ImagesToPdfArgs(
        images: [(a, 'beach.jpg'), (b, 'sunset.jpg')],
        outputDir: tempOut.path,
      ),
    );
    expect(r2.outputPath.split(Platform.pathSeparator).last, 'beach_plus1.pdf');
  });
}
