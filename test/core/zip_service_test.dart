import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/zip_service.dart';

Uint8List makeZip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory tempOut;
  late Directory tempIn;

  setUp(() {
    tempOut = Directory.systemTemp.createTempSync('pf_zip_out');
    tempIn = Directory.systemTemp.createTempSync('pf_zip_in');
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

  // ---------------------------------------------------------------- create

  test('create packs files into a valid zip with deduped duplicate names', () async {
    final a = write('a1.txt', 'hello'.codeUnits);
    final b = write('b.png', List.filled(300, 0x89));
    final c = write('a2.txt', 'world'.codeUnits); // distinct files, same display name

    final result = await zipCreateTask(
      ZipCreateArgs(
        items: [
          ZipCreateItem(path: a, name: 'a.txt'),
          ZipCreateItem(path: b, name: 'b.png'),
          ZipCreateItem(path: c, name: 'a.txt'),
        ],
        outputDir: tempOut.path,
      ),
    );

    expect(result.fileCount, 3);
    final zip = ZipDecoder().decodeBytes(File(result.zipPath).readAsBytesSync());
    final names = zip.map((f) => f.name).toList();
    expect(names, containsAll(['a.txt', 'b.png', 'a (1).txt']));
    final aEntry = zip.firstWhere((f) => f.name == 'a.txt');
    expect(String.fromCharCodes(aEntry.content as List<int>), 'hello');
  });

  test('create skips vanished inputs and reports them; all vanished → error', () async {
    final ghost = '${tempIn.path}${Platform.pathSeparator}ghost.txt';
    final real = write('real.txt', 'x'.codeUnits);

    final result = await zipCreateTask(
      ZipCreateArgs(
        items: [
          ZipCreateItem(path: ghost, name: 'ghost.txt'),
          ZipCreateItem(path: real, name: 'real.txt'),
        ],
        outputDir: tempOut.path,
      ),
    );
    expect(result.failedNames, contains('ghost.txt'));
    expect(result.fileCount, 1);

    await expectLater(
      zipCreateTask(
        ZipCreateArgs(
          items: [ZipCreateItem(path: ghost, name: 'ghost.txt')],
          outputDir: tempOut.path,
        ),
      ),
      throwsA(isA<PureError>()),
    );
  });

  // --------------------------------------------------------------- extract

  test('extract restores files and nested folders, dedupes name clashes', () async {
    final zip = write('bundle.zip', makeZip({
      'docs/readme.txt': 'read me'.codeUnits,
      'img.png': List.filled(64, 0x50),
    }));
    // Separate archive with a case-clash pair (IMG.png vs img.png). Identical
    // duplicate entry names are collapsed by archive's decoder at decode time,
    // but case-clashes survive decode and must be deduped on disk.
    final archive = Archive()
      ..add(ArchiveFile('docs/readme.txt', 7, 'read me'.codeUnits))
      ..add(ArchiveFile('IMG.png', 4, [1, 2, 3, 4]))
      ..add(ArchiveFile('img.png', 4, [5, 6, 7, 8]));
    final dupZip = write('dup.zip', Uint8List.fromList(ZipEncoder().encode(archive)));

    final result = await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );
    expect(result.fileCount, 2);
    expect(
      File('${result.folderPath}${Platform.pathSeparator}docs${Platform.pathSeparator}readme.txt')
          .readAsStringSync(),
      'read me',
    );

    final dupResult = await zipExtractTask(
      ZipExtractArgs(zipPath: dupZip, outputDir: tempOut.path),
    );
    expect(dupResult.fileCount, 3, reason: 'case-clash pair gets (1) suffixes');
    final dupNames = dupResult.filePaths
        .map((p) => p.split(Platform.pathSeparator).last)
        .toList();
    expect(dupNames, containsAllInOrder(['IMG.png', 'img (1).png']));
  });

  test('ZIP SLIP: entry with .. escapes nothing and aborts the extract', () async {
    final archive = Archive()
      ..add(ArchiveFile('ok.txt', 2, [1, 2]))
      ..add(ArchiveFile('../../../evil.txt', 2, [3, 4]));
    final zip = write('evil.zip', Uint8List.fromList(ZipEncoder().encode(archive)));
    final before = _snapshot(tempOut);

    await expectLater(
      zipExtractTask(
        ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
      ),
      throwsA(isA<ZipSlipDetected>()),
    );

    // Nothing may be written from a hostile archive — not even the good file.
    expect(_snapshot(tempOut), before);
    // And nothing escaped above the output dir.
    expect(File('${tempOut.parent.path}${Platform.pathSeparator}evil.txt').existsSync(), isFalse);
  });

  test('absolute-path and drive-letter entries land inside the folder (sanitized)', () async {
    final archive = Archive()
      ..add(ArchiveFile('/etc/innocent.txt', 3, [9, 9, 9]))
      ..add(ArchiveFile('C:/windows/other.txt', 3, [8, 8, 8]));
    final zip = write('abs.zip', Uint8List.fromList(ZipEncoder().encode(archive)));

    final result = await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );

    expect(result.fileCount, 2);
    for (final p in result.filePaths) {
      expect(p.startsWith(result.folderPath), isTrue,
          reason: '$p must stay inside ${result.folderPath}');
    }
  });

  test('ZIP BOMB: declared size above ratio cap is rejected before extraction', () async {
    // A ~50 KB archive claiming to expand to ~2 GB (> ratio cap × archive).
    final archive = Archive()
      ..add(ArchiveFile('boom.bin', 2 * 1024 * 1024 * 1024, List.filled(10, 0)));
    final tiny = write('bomb.zip', Uint8List.fromList(ZipEncoder().encode(archive)));
    final before = _snapshot(tempOut);

    await expectLater(
      zipExtractTask(
        ZipExtractArgs(zipPath: tiny, outputDir: tempOut.path),
      ),
      throwsA(isA<ZipBombDetected>()),
    );
    expect(_snapshot(tempOut), before);
  });

  test('legitimate high-ratio archive under the floor cap extracts fine', () async {
    // Declared 1 KB expansion from a tiny archive — well under the floor.
    final archive = Archive()
      ..add(ArchiveFile('big.txt', 1024, List.filled(1024, 0x61)));
    final zip = write('fine.zip', Uint8List.fromList(ZipEncoder().encode(archive)));

    final result = await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );
    expect(result.fileCount, 1);
    expect(result.totalBytes, 1024);
  });

  test('empty archive (no file entries) → typed error', () async {
    final archive = Archive()..add(ArchiveFile('only-a-folder/', 0, const []));
    final zip = write('empty.zip', Uint8List.fromList(ZipEncoder().encode(archive)));

    await expectLater(
      zipExtractTask(
        ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
      ),
      throwsA(isA<PureError>()),
    );
  });

  test('cancel aborts mid-extract with nothing written (edge #50)', () async {
    final archive = Archive()
      ..add(ArchiveFile('a.txt', 2, [1, 2]))
      ..add(ArchiveFile('b.txt', 2, [3, 4]));
    final zip = write('two.zip', Uint8List.fromList(ZipEncoder().encode(archive)));

    await expectLater(
      zipExtractTask(
        ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });

  test('ORIGINALS SACRED: the zip itself is never modified (F7)', () async {
    final zipBytes = makeZip({'x.txt': 'hi'.codeUnits});
    final zip = write('x.zip', zipBytes);

    await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );

    expect(File(zip).readAsBytesSync(), zipBytes);
  });

  test('extract outputs never overwrite earlier results', () async {
    final zip = write('same.zip', makeZip({'f.txt': 'v'.codeUnits}));

    final r1 = await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );
    final r2 = await zipExtractTask(
      ZipExtractArgs(zipPath: zip, outputDir: tempOut.path),
    );
    expect(r1.folderPath == r2.folderPath, isFalse);
  });
}

Map<String, int> _snapshot(Directory dir) {
  if (!dir.existsSync()) return {};
  return {
    for (final e in dir.listSync(recursive: true))
      e.path: e is File ? e.lengthSync() : -1,
  };
}
