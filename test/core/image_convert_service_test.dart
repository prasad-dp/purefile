import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/image_convert_service.dart';

Uint8List makeNoisyJpeg({int width = 1200, int height = 900}) {
  final image = img.Image(width: width, height: height);
  var seed = 4242;
  for (final p in image) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    final v = (seed >> 16) & 0xFF;
    p.setRgb(v, (v * 7) % 256, (v * 13) % 256);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

Uint8List makeTransparentPng({int width = 200, int height = 200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(50, 100, 200, 128));
  return Uint8List.fromList(img.encodePng(image));
}

bool isJpegSig(List<int> b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;
bool isPngSig(List<int> b) =>
    b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
bool isWebpSig(List<int> b) =>
    b.length > 12 &&
    b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && // RIFF
    b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // WEBP

void main() {
  late Directory tempOut;
  late Directory tempIn;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_conv_out');
    tempIn = Directory.systemTemp.createTempSync('pf_conv_in');
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

  test('PNG → JPG produces a real JPEG with alpha flattened to white', () async {
    final src = write('shot.png', makeTransparentPng());

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'shot.png')],
        outputDir: tempOut.path,
        target: ImageTarget.jpeg,
      ),
    );

    final f = result.files.single;
    expect(f.converted, isTrue);
    expect(f.name, 'shot.jpg');
    final bytes = File(f.path).readAsBytesSync();
    expect(isJpegSig(bytes), isTrue);
    // Decode and check the formerly-transparent corner is now opaque white-ish.
    final out = img.decodeImage(bytes)!;
    expect(out.getPixel(0, 0).a, 255);
  });

  test('JPG → PNG produces a real PNG', () async {
    final src = write('photo.jpg', makeNoisyJpeg());

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'photo.jpg')],
        outputDir: tempOut.path,
        target: ImageTarget.png,
      ),
    );

    final f = result.files.single;
    expect(f.name, 'photo.png');
    expect(isPngSig(File(f.path).readAsBytesSync()), isTrue);
  });

  test('PNG → WebP produces a real WebP', () async {
    final src = write('art.png', makeTransparentPng());

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'art.png')],
        outputDir: tempOut.path,
        target: ImageTarget.webp,
      ),
    );

    final f = result.files.single;
    expect(f.name, 'art.webp');
    expect(isWebpSig(File(f.path).readAsBytesSync()), isTrue);
  });

  test('same format is copied through byte-identical (no useless re-encode)', () async {
    final srcBytes = makeNoisyJpeg();
    final src = write('same.jpg', srcBytes);

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'same.jpg')],
        outputDir: tempOut.path,
        target: ImageTarget.jpeg,
      ),
    );

    final f = result.files.single;
    expect(f.converted, isFalse);
    expect(File(f.path).readAsBytesSync(), srcBytes);
  });

  test('.jpeg extension normalizes to .jpg output name', () async {
    final src = write('old.jpeg', makeNoisyJpeg());

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'old.jpeg')],
        outputDir: tempOut.path,
        target: ImageTarget.jpeg,
      ),
    );

    expect(result.files.single.converted, isFalse, reason: 'jpeg→jpeg is same format');
    expect(result.files.single.name, 'old.jpg');
  });

  test('EXIF-rotated photo converts upright', () async {
    final image = img.Image(width: 800, height: 600);
    img.fill(image, color: img.ColorRgb8(200, 120, 120));
    final jpeg = img.encodeJpg(image, quality: 95);
    final exif = img.ExifData()..imageIfd.orientation = 6;
    final injected = img.injectJpgExif(jpeg, exif);
    final src = write('rotated.jpg', injected ?? jpeg);

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [ImageConvertItem(path: src, name: 'rotated.jpg')],
        outputDir: tempOut.path,
        target: ImageTarget.png,
      ),
    );

    final out = img.decodeImage(File(result.files.single.path).readAsBytesSync())!;
    expect(out.width, 600, reason: 'orientation 6 swaps dimensions');
    expect(out.height, 800);
  });

  test('mixed batch → per-file outputs + zip with every result', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final b = write('b.png', makeTransparentPng());

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [
          ImageConvertItem(path: a, name: 'a.jpg'),
          ImageConvertItem(path: b, name: 'b.png'),
        ],
        outputDir: tempOut.path,
        target: ImageTarget.png,
      ),
    );

    expect(result.files.length, 2);
    expect(result.zipPath, isNotNull);
    final zip = ZipDecoder().decodeBytes(File(result.zipPath!).readAsBytesSync());
    expect(zip.map((f) => f.name), containsAll(['a.png', 'b.png']));
  });

  test('corrupt image skipped, rest converted (partial success)', () async {
    // 0-byte file (interrupted transfer) — the one reliably undecodable
    // input: the pure-Dart decoders are lenient enough to "decode" junk and
    // truncated streams into non-null garbage (no-magic TGA accepts almost
    // anything).
    final junk = write('junk.jpg', const <int>[]);
    final ok = write('ok.jpg', makeNoisyJpeg(width: 800, height: 600));

    final result = await imageConvertTask(
      ImageConvertArgs(
        items: [
          ImageConvertItem(path: junk, name: 'junk.jpg'),
          ImageConvertItem(path: ok, name: 'ok.jpg'),
        ],
        outputDir: tempOut.path,
        target: ImageTarget.png,
      ),
    );

    expect(result.files.length, 1);
    expect(result.files.single.name, 'ok.png');
  });  test('all corrupt → typed error, no output', () async {
    final junk = write('junk.jpg', const <int>[]);

    await expectLater(
      imageConvertTask(
        ImageConvertArgs(
          // Target ≠ file format so it takes the decode path (same-format
          // requests copy through and must never fail).
          items: [ImageConvertItem(path: junk, name: 'junk.jpg')],
          outputDir: tempOut.path,
          target: ImageTarget.png,
        ),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before writing (edge #50)', () async {
    final a = write('a.jpg', makeNoisyJpeg());

    await expectLater(
      imageConvertTask(
        ImageConvertArgs(
          items: [ImageConvertItem(path: a, name: 'a.jpg')],
          outputDir: tempOut.path,
          target: ImageTarget.png,
        ),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: source images untouched (F7)', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final b = write('b.png', makeTransparentPng());
    final beforeA = File(a).readAsBytesSync();
    final beforeB = File(b).readAsBytesSync();

    await imageConvertTask(
      ImageConvertArgs(
        items: [
          ImageConvertItem(path: a, name: 'a.jpg'),
          ImageConvertItem(path: b, name: 'b.png'),
        ],
        outputDir: tempOut.path,
        target: ImageTarget.webp,
      ),
    );

    expect(File(a).readAsBytesSync(), beforeA);
    expect(File(b).readAsBytesSync(), beforeB);
  });

  test('outputs never overwrite earlier results', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final args = ImageConvertArgs(
      items: [ImageConvertItem(path: a, name: 'a.jpg')],
      outputDir: tempOut.path,
      target: ImageTarget.png,
    );

    final r1 = await imageConvertTask(args);
    final r2 = await imageConvertTask(args);
    expect(r1.files.single.path == r2.files.single.path, isFalse);
  });
}
