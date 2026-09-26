import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/file_io.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pf_file_io_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('uniqueDestination', () {
    test('returns the plain name when free', () {
      final path = uniqueDestination(temp.path, 'report.pdf');
      expect(path.endsWith('report.pdf'), isTrue);
    });

    test('auto-numbers on collision, never overwrites (edge #31/#33)', () {
      File('${temp.path}${Platform.pathSeparator}report.pdf').writeAsBytesSync([1]);
      final second = uniqueDestination(temp.path, 'report.pdf');
      expect(second, contains('report (2).pdf'));
      File(second).writeAsBytesSync([2]);
      final third = uniqueDestination(temp.path, 'report.pdf');
      expect(third, contains('report (3).pdf'));
    });

    test('handles names without extension', () {
      File('${temp.path}${Platform.pathSeparator}notes').writeAsBytesSync([1]);
      expect(uniqueDestination(temp.path, 'notes'), contains('notes (2)'));
    });
  });

  group('atomicWriteBytes', () {
    test('writes the target and leaves no temp behind', () async {
      final target = '${temp.path}${Platform.pathSeparator}out.bin';
      await atomicWriteBytes(target, Uint8List.fromList([9, 9, 9]));
      expect(File(target).readAsBytesSync(), [9, 9, 9]);
      expect(File('$target$kPfTempSuffix').existsSync(), isFalse);
    });
  });

  group('atomicCopyFile', () {
    test('copies bytes and reports progress to 1.0', () async {
      final src = File('${temp.path}${Platform.pathSeparator}src.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(300000, 7)));
      final dst = '${temp.path}${Platform.pathSeparator}dst.bin';

      final fractions = <double>[];
      final written = await atomicCopyFile(src.path, dst, onProgress: fractions.add);

      expect(written, 300000);
      expect(File(dst).lengthSync(), 300000);
      expect(fractions.last, 1.0);
      expect(File('$dst$kPfTempSuffix').existsSync(), isFalse);
    });

    test('cancel from the start throws JobCancelled, leaves no output (edge #50)', () async {
      final src = File('${temp.path}${Platform.pathSeparator}big.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(1024 * 1024, 1)));
      final dst = '${temp.path}${Platform.pathSeparator}out.bin';

      await expectLater(
        atomicCopyFile(src.path, dst, isCancelled: () => true),
        throwsA(isA<JobCancelled>()),
      );
      expect(File(dst).existsSync(), isFalse);
      expect(File('$dst$kPfTempSuffix').existsSync(), isFalse);
    });

    test('isCancelled=true from the start throws and cleans up', () async {
      final src = File('${temp.path}${Platform.pathSeparator}big2.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(1024 * 1024, 1)));
      final dst = '${temp.path}${Platform.pathSeparator}out2.bin';
      await expectLater(
        atomicCopyFile(src.path, dst, isCancelled: () => true),
        throwsA(isA<JobCancelled>()),
      );
      expect(File('$dst$kPfTempSuffix').existsSync(), isFalse);
    });
  });

  group('cleanupTempFiles', () {
    test('sweeps orphans but keeps real outputs (edge #36)', () {
      File('${temp.path}${Platform.pathSeparator}keep.bin').writeAsBytesSync([1]);
      File('${temp.path}${Platform.pathSeparator}lost.bin$kPfTempSuffix')
          .writeAsBytesSync([1]);
      cleanupTempFiles(temp.path);
      expect(File('${temp.path}${Platform.pathSeparator}keep.bin').existsSync(), isTrue);
      expect(File('${temp.path}${Platform.pathSeparator}lost.bin$kPfTempSuffix').existsSync(),
          isFalse);
    });
  });

  group('secureDelete', () {
    test('removes the file', () async {
      final f = File('${temp.path}${Platform.pathSeparator}secret.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(10000, 3)));
      await secureDelete(f.path);
      expect(f.existsSync(), isFalse);
    });
  });
}
