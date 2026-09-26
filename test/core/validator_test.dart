import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/formats.dart';
import 'package:purefile/core/validation/validator.dart';

Uint8List _pdfBytes({int size = 1024}) => Uint8List.fromList(
      ['%PDF-1.4\n'.codeUnits, List.filled(size - 8, 0x20)].expand((x) => x).toList(),
    );

Uint8List _pngBytes() => Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 0)],
    );

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pf_validator_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final path = '${temp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  group('validatePick — size rules', () {
    test('accepts a valid small PDF (edge #2 baseline)', () async {
      final result = await validatePick([write('doc.pdf', _pdfBytes())]);
      expect(result.accepted, hasLength(1));
      expect(result.rejected, isEmpty);
    });

    test('rejects a 0-byte file (edge #5)', () async {
      final result = await validatePick([write('empty.pdf', const [])]);
      expect(result.accepted, isEmpty);
      expect(result.rejected.single.$2, isA<CorruptedFile>());
    });

    test('rejects oversized file with FileTooLarge (edge #1)', () async {
      final big = Uint8List.fromList(
        ['%PDF-1.4\n'.codeUnits, List.filled(51 * 1024 * 1024, 0x20)].expand((x) => x).toList(),
      );
      final result = await validatePick([write('big.pdf', big)]);
      expect(result.rejected.single.$2, isA<FileTooLarge>());
    });

    test('batch: 9 valid + 1 oversized → 9 accepted, 1 rejected (edge #3)', () async {
      final paths = <String>[];
      for (var i = 0; i < 9; i++) {
        paths.add(write('ok$i.pdf', _pdfBytes(size: 512 + i)));
      }
      final big = Uint8List.fromList(
        ['%PDF-1.4\n'.codeUnits, List.filled(51 * 1024 * 1024, 0x20)].expand((x) => x).toList(),
      );
      paths.add(write('huge.pdf', big));

      final result = await validatePick(paths);
      expect(result.accepted, hasLength(9));
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.$1, 'huge.pdf');
    });
  });

  group('validatePick — magic bytes', () {
    test('rejects junk bytes named .pdf (edge #6)', () async {
      final result = await validatePick(
          [write('junk.pdf', List.filled(256, 0xAA))]);
      expect(result.accepted, isEmpty);
      expect(result.rejected.single.$2, isA<CorruptedFile>());
    });

    test('rejects junk bytes named .png (edge #7)', () async {
      final result = await validatePick(
          [write('junk.png', List.filled(256, 0xBB))]);
      expect(result.accepted, isEmpty);
      expect(result.rejected.single.$2, isA<CorruptedFile>());
    });

    test('rejects a PDF renamed to .png (extension/content mismatch)', () async {
      final result = await validatePick([write('notpng.png', _pdfBytes())]);
      expect(result.accepted, isEmpty);
      expect(result.rejected.single.$2, isA<UnsupportedFormat>());
    });

    test('tool allow-list: PDF not accepted into an image-only tool (edge #16)', () async {
      final result = await validatePick(
        [write('doc.pdf', _pdfBytes())],
        allowedMagic: {PfMagic.png, PfMagic.jpeg, PfMagic.webp},
      );
      expect(result.accepted, isEmpty);
      expect(result.rejected.single.$2, isA<UnsupportedFormat>());
    });

    test('tool allow-list accepts matching image', () async {
      final result = await validatePick(
        [write('img.png', _pngBytes())],
        allowedMagic: {PfMagic.png, PfMagic.jpeg, PfMagic.webp},
      );
      expect(result.accepted, hasLength(1));
    });
  });

  group('validateBatch', () {
    test('throws BatchTooHeavy above 100 MB combined (edge #4)', () {
      final files = List.generate(
        3,
        (i) => PickedFile(
          path: 'p$i',
          name: 'p$i.pdf',
          sizeBytes: 40 * 1024 * 1024,
          magic: PfMagic.pdf,
        ),
      );
      expect(
        () => validateBatch(files, outputDirectory: temp.path),
        throwsA(isA<BatchTooHeavy>()),
      );
    });

    test('throws BatchTooLarge above 30 files (edge #37 precondition)', () {
      final files = List.generate(
        31,
        (i) => PickedFile(
            path: 'p$i', name: 'p$i.pdf', sizeBytes: 10, magic: PfMagic.pdf),
      );
      expect(
        () => validateBatch(files, outputDirectory: temp.path),
        throwsA(isA<BatchTooLarge>()),
      );
    });

    test('passes for a normal batch (storage check skips when df unavailable)',
        () {
      final files = List.generate(
        3,
        (i) => PickedFile(
            path: 'p$i', name: 'p$i.pdf', sizeBytes: 1024, magic: PfMagic.pdf),
      );
      expect(
        () => validateBatch(files, outputDirectory: temp.path),
        returnsNormally,
      );
    });
  });
}
