import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/file_io.dart';
import 'package:purefile/core/pdf/pdf_compress_service.dart';
import 'package:purefile/core/validation/validator.dart';
import 'package:purefile/core/vault/vault_store.dart';
import 'package:purefile/features/tools/tool_flow_screen.dart' show toolUiSpec;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pf_hardening');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('filenames that break naive code', () {
    test('uniqueDestination handles emoji, unicode and spaces', () {
      File('${root.path}${Platform.pathSeparator}报表 📊 tax (final).pdf')
          .writeAsBytesSync([1]);
      final next = uniqueDestination(root.path, '报表 📊 tax (final).pdf');
      expect(next, contains('(2)'));
      expect(File(next).existsSync(), isFalse);
    });

    test('long names (200 chars) round-trip unique naming', () {
      final longName = '${'x' * 196}.pdf';
      File('${root.path}${Platform.pathSeparator}$longName')
          .writeAsBytesSync([1]);
      final next = uniqueDestination(root.path, longName);
      expect(next, contains('(2)'));
    });

    test('vault round-trips emoji + unicode + long filenames', () async {
      final vaultDir = Directory(
          '${root.path}${Platform.pathSeparator}vault')
        ..createSync();
      final vault = VaultStore(
          rootDir: vaultDir.path, keyStorage: InMemoryKeyStorage());
      await vault.initialize('long enough secret');

      final longName = '${'y' * 180}.bin';
      final names = [
        '报表 📊.pdf',
        'отчёт годовой.png',
        'naïve résumé — final (v2).zip',
        'emoji-🚀💥-name.jpg',
        longName,
      ];
      for (final name in names) {
        final src = File('${root.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(Uint8List.fromList([9, 8, 7, 6]));
        final item = await vault.importFile(src.path);
        expect(item.name, name, reason: 'name preserved through import');
        final out = await vault.exportTo(item.id, root.path);
        expect(out.endsWith(name), isTrue,
            reason: 'export restores the exact name');
        expect(File(out).readAsBytesSync(), [9, 8, 7, 6]);
      }
    });
  });

  group('corrupt-input sweep: no tool crashes on garbage', () {
    final garbage = <String, List<int>>{
      'zero-byte': [],
      'random-noise': [for (var i = 0; i < 128; i++) (i * 37 + 11) % 256],
      // A real PDF header cut off after 4 bytes — magic present, body missing.
      'truncated-pdf': [0x25, 0x50, 0x44, 0x46],
      // PNG signature followed by junk.
      'png-then-junk': [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4],
    };

    test('every tool spec rejects every garbage input with a typed reason',
        () async {
      for (final entry in garbage.entries) {
        final path =
            '${root.path}${Platform.pathSeparator}garbage-${entry.key}.pdf';
        File(path).writeAsBytesSync(entry.value);
        for (final toolId in [
          'pdf_compress',
          'pdf_merge',
          'pdf_split',
          'images_to_pdf',
          'pdf_to_images',
          'image_compress',
          'image_convert',
          'zip_create',
          'zip_extract',
          'ocr',
        ]) {
          final spec = toolUiSpec(toolId);
          final result = await validatePick(
            [path],
            allowedMagic: spec.allowedMagic,
          );
          // zip_create accepts any file — the others must refuse cleanly.
          if (toolId == 'zip_create') continue;
          // A header-valid but truncated PDF passes the FAST magic gate by
          // design — the tool's probe layer is its typed second defense.
          if (entry.key == 'truncated-pdf' &&
              const {'pdf_compress', 'pdf_merge', 'pdf_split', 'pdf_to_images', 'ocr'}
                  .contains(toolId)) {
            continue;
          }
          expect(result.accepted, isEmpty,
              reason: '${entry.key} must not reach $toolId');
          expect(result.rejected, isNotEmpty,
              reason: '${entry.key} must produce a typed rejection for $toolId');
        }
      }
    });

    test('truncated PDF: tool-level probe rejects what the magic gate passed',
        () async {
      final path =
          '${root.path}${Platform.pathSeparator}garbage-truncated-pdf.pdf';
      File(path).writeAsBytesSync(garbage['truncated-pdf']!);
      await expectLater(
        pdfCompressTask(
          PdfCompressArgs(
            inputPath: path,
            outputPath:
                '${root.path}${Platform.pathSeparator}out.pdf',
            quality: PdfCompressQuality.medium,
          ),
        ),
        throwsA(isA<CorruptedFile>()),
      );
      expect(
        File('${root.path}${Platform.pathSeparator}out.pdf').existsSync(),
        isFalse,
        reason: 'failed probe must write nothing',
      );
    });

    test('garbage never lands on disk through the vault', () async {
      final vaultDir = Directory(
          '${root.path}${Platform.pathSeparator}vault')
        ..createSync();
      final vault = VaultStore(
          rootDir: vaultDir.path, keyStorage: InMemoryKeyStorage());
      await vault.initialize('long enough secret');
      // The vault intentionally accepts any bytes (it's a storage box, not a
      // format gate) — but the operation must round-trip, not corrupt.
      final src = File('${root.path}${Platform.pathSeparator}noise.bin')
        ..writeAsBytesSync([for (var i = 0; i < 64; i++) (i * 91) % 256]);
      final item = await vault.importFile(src.path);
      final out = await vault.exportTo(item.id, root.path);
      expect(File(out).readAsBytesSync(), src.readAsBytesSync());
    });
  });

  group('write reliability', () {
    test('parallel atomic writes never collide or corrupt', () async {
      await Future.wait([
        for (var i = 0; i < 12; i++)
          atomicWriteBytes(
            '${root.path}${Platform.pathSeparator}out-$i.bin',
            Uint8List.fromList([for (var j = 0; j < 512; j++) j % 256]),
          ),
      ]);
      for (var i = 0; i < 12; i++) {
        final f = File('${root.path}${Platform.pathSeparator}out-$i.bin');
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), 512);
        expect(f.readAsBytesSync()[0], 0);
      }
      expect(
        root.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.pf-tmp'),
            ),
        isEmpty,
        reason: 'no temp files may survive successful writes',
      );
    });

    test('cleanupTempFiles removes orphans without touching real files',
        () async {
      File('${root.path}${Platform.pathSeparator}keep.pdf')
          .writeAsBytesSync([1, 2, 3]);
      File('${root.path}${Platform.pathSeparator}orphan.pdf.pf-tmp')
          .writeAsBytesSync([9, 9, 9]);
      cleanupTempFiles(root.path);
      expect(
        File('${root.path}${Platform.pathSeparator}orphan.pdf.pf-tmp')
            .existsSync(),
        isFalse,
      );
      expect(
        File('${root.path}${Platform.pathSeparator}keep.pdf').existsSync(),
        isTrue,
      );
    });
  });
}
