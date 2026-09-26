import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/image_compress_service.dart';

Uint8List makeNoisyJpeg({int width = 1200, int height = 900, int quality = 98}) {
  // Pseudo-random noise compresses poorly — guarantees room to shrink.
  final image = img.Image(width: width, height: height);
  var seed = 12345;
  for (final p in image) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    final v = (seed >> 16) & 0xFF;
    p.setRgb(v, (v * 7) % 256, (v * 13) % 256);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

Uint8List makePng({int width = 300, int height = 300}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 180, 240));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tempOut;
  late Directory tempIn;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_ic_out');
    tempIn = Directory.systemTemp.createTempSync('pf_ic_in');
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

  test('JPEG shrinks at all presets; lower quality = smaller', () async {
    final path = write('photo.jpg', makeNoisyJpeg());
    final original = File(path).lengthSync();

    final sizes = <ImageQuality, int>{};
    for (final q in ImageQuality.values) {
      final result = await imageCompressTask(
        ImageCompressArgs(
          items: [ImageCompressItem(path: path, name: 'photo.jpg')],
          outputDir: tempOut.path,
          quality: q,
        ),
      );
      sizes[q] = result.files.single.sizeBytes;
      expect(result.files.single.keptOriginal, isFalse, reason: '$q should shrink');
      // Re-encoded at lower quality than 98 must be smaller.
      expect(sizes[q]!, lessThan(original));
    }
    expect(sizes[ImageQuality.low]!, lessThanOrEqualTo(sizes[ImageQuality.medium]!));
    expect(sizes[ImageQuality.medium]!, lessThanOrEqualTo(sizes[ImageQuality.high]!));
  });

  test('never worse than input: already-tiny image keeps original bytes', () async {
    // A 40×40 solid PNG is incompressible; re-encode won't beat it.
    final tiny = write('tiny.png', makePng(width: 40, height: 40));
    final before = File(tiny).readAsBytesSync();

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [ImageCompressItem(path: tiny, name: 'tiny.png')],
        outputDir: tempOut.path,
        quality: ImageQuality.low,
      ),
    );

    expect(result.files.single.keptOriginal, isTrue);
    expect(File(result.files.single.path).readAsBytesSync(), before);
  });

  test('EXIF-rotated photo comes out upright (orientation baked)', () async {
    final image = img.Image(width: 800, height: 600);
    img.fill(image, color: img.ColorRgb8(200, 120, 120));
    final jpeg = img.encodeJpg(image, quality: 95);
    final exif = img.ExifData()..imageIfd.orientation = 6;
    final injected = img.injectJpgExif(jpeg, exif);
    final path = write('rotated.jpg', injected ?? jpeg);

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [ImageCompressItem(path: path, name: 'rotated.jpg')],
        outputDir: tempOut.path,
        quality: ImageQuality.high,
      ),
    );

    final out = img.decodeImage(File(result.files.single.path).readAsBytesSync())!;
    expect(out.width, 600, reason: 'orientation 6 swaps dimensions');
    expect(out.height, 800);
  });

  test('downscale caps the longest side, aspect preserved', () async {
    final path = write('big.jpg', makeNoisyJpeg(width: 4000, height: 2000));

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [ImageCompressItem(path: path, name: 'big.jpg')],
        outputDir: tempOut.path,
        quality: ImageQuality.high,
        maxSide: 2560,
      ),
    );

    final out = img.decodeImage(File(result.files.single.path).readAsBytesSync())!;
    expect(out.width, 2560);
    expect(out.height, 1280);
  });

  test('downscale skipped when image already under the cap', () async {
    final path = write('small.jpg', makeNoisyJpeg(width: 1200, height: 900));

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [ImageCompressItem(path: path, name: 'small.jpg')],
        outputDir: tempOut.path,
        quality: ImageQuality.high,
        maxSide: 2560,
      ),
    );

    final out = img.decodeImage(File(result.files.single.path).readAsBytesSync())!;
    expect(out.width, 1200);
    expect(out.height, 900);
  });

  test('mixed batch: per-file outputs + zip; zip contains every result', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final b = write('b.png', makePng());

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [
          ImageCompressItem(path: a, name: 'a.jpg'),
          ImageCompressItem(path: b, name: 'b.png'),
        ],
        outputDir: tempOut.path,
        quality: ImageQuality.medium,
      ),
    );

    expect(result.files.length, 2);
    expect(result.zipPath, isNotNull);
    final zip = ZipDecoder().decodeBytes(File(result.zipPath!).readAsBytesSync());
    expect(zip.map((f) => f.name), containsAll(['a_compressed.jpg', 'b_compressed.png']));
  });

  test('corrupt image skipped, rest processed (partial success)', () async {
    final junk = write('junk.png', List.filled(200, 0x77));
    final ok = write('ok.jpg', makeNoisyJpeg(width: 800, height: 600));

    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [
          ImageCompressItem(path: junk, name: 'junk.png'),
          ImageCompressItem(path: ok, name: 'ok.jpg'),
        ],
        outputDir: tempOut.path,
        quality: ImageQuality.medium,
      ),
    );

    expect(result.files.length, 1);
    expect(result.files.single.name, 'ok_compressed.jpg');
  });

  test('all corrupt → typed error, no output', () async {
    final junk = write('junk.png', List.filled(200, 0x88));

    await expectLater(
      imageCompressTask(
        ImageCompressArgs(
          items: [ImageCompressItem(path: junk, name: 'junk.png')],
          outputDir: tempOut.path,
          quality: ImageQuality.medium,
        ),
      ),
      throwsA(isA<PureError>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('cancel aborts before writing (edge #50)', () async {
    final a = write('a.jpg', makeNoisyJpeg());

    await expectLater(
      imageCompressTask(
        ImageCompressArgs(
          items: [ImageCompressItem(path: a, name: 'a.jpg')],
          outputDir: tempOut.path,
          quality: ImageQuality.medium,
        ),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: source images untouched (F7)', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final b = write('b.png', makePng());
    final beforeA = File(a).readAsBytesSync();
    final beforeB = File(b).readAsBytesSync();

    await imageCompressTask(
      ImageCompressArgs(
        items: [
          ImageCompressItem(path: a, name: 'a.jpg'),
          ImageCompressItem(path: b, name: 'b.png'),
        ],
        outputDir: tempOut.path,
        quality: ImageQuality.low,
      ),
    );

    expect(File(a).readAsBytesSync(), beforeA);
    expect(File(b).readAsBytesSync(), beforeB);
  });

  test('outputs never overwrite earlier results', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final args = ImageCompressArgs(
      items: [ImageCompressItem(path: a, name: 'a.jpg')],
      outputDir: tempOut.path,
      quality: ImageQuality.medium,
    );

    final r1 = await imageCompressTask(args);
    final r2 = await imageCompressTask(args);
    expect(r1.files.single.path == r2.files.single.path, isFalse);
  });

  test('savedPercent reflects the batch', () async {
    final a = write('a.jpg', makeNoisyJpeg());
    final result = await imageCompressTask(
      ImageCompressArgs(
        items: [ImageCompressItem(path: a, name: 'a.jpg')],
        outputDir: tempOut.path,
        quality: ImageQuality.low,
      ),
    );
    expect(result.savedPercent, greaterThan(0));
    expect(result.savedPercent, lessThanOrEqualTo(100));
  });
}
