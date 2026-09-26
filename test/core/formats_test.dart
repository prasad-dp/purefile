import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/formats.dart';

Uint8List _bytes(List<int> list) => Uint8List.fromList(list);

void main() {
  group('sniffMagic', () {
    test('detects PDF', () {
      expect(sniffMagic(_bytes([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34])), PfMagic.pdf);
    });

    test('detects PNG', () {
      expect(
        sniffMagic(_bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        PfMagic.png,
      );
    });

    test('detects JPEG', () {
      expect(sniffMagic(_bytes([0xFF, 0xD8, 0xFF, 0xE0])), PfMagic.jpeg);
    });

    test('detects WebP (RIFF…WEBP)', () {
      final head = _bytes([
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, //
        0x57, 0x45, 0x42, 0x50,
      ]);
      expect(sniffMagic(head), PfMagic.webp);
    });

    test('detects ZIP (PK)', () {
      expect(sniffMagic(_bytes([0x50, 0x4B, 0x03, 0x04])), PfMagic.zip);
    });

    test('junk bytes are unknown', () {
      expect(sniffMagic(_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])),
          PfMagic.unknown);
    });

    test('HEIC brand detection', () {
      final head = _bytes([
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // ftyp at offset 4
        0x68, 0x65, 0x69, 0x63, // heic
      ]);
      expect(sniffMagic(head), PfMagic.heic);
    });
  });

  group('magicForExtension', () {
    test('maps known extensions', () {
      expect(magicForExtension('report.pdf'), {PfMagic.pdf});
      expect(magicForExtension('photo.JPG'), {PfMagic.jpeg});
      expect(magicForExtension('archive.zip'), {PfMagic.zip});
    });

    test('unknown or missing extension returns null (allowed through)', () {
      expect(magicForExtension('data.bin'), isNull);
      expect(magicForExtension('noext'), isNull);
    });
  });
}
