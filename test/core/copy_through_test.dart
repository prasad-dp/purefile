import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/jobs/copy_through_service.dart';

void main() {
  late Directory tempIn;
  late Directory tempOut;

  setUp(() {
    tempIn = Directory.systemTemp.createTempSync('pf_ct_in');
    tempOut = Directory.systemTemp.createTempSync('pf_ct_out');
  });

  tearDown(() {
    tempIn.deleteSync(recursive: true);
    tempOut.deleteSync(recursive: true);
  });

  String makeInput(String name, List<int> bytes) {
    final path = '${tempIn.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('copies files, unique names, progress reaches 1.0', () async {
    final a = makeInput('a.txt', List.filled(100000, 1));
    final b = makeInput('b.txt', List.filled(200000, 2));

    final fractions = <double>[];
    final result = await copyThrough(
      CopyThroughArgs(
        jobs: [(a, 'a.txt', 100000), (b, 'b.txt', 200000)],
        outputDir: tempOut.path,
      ),
      onProgress: (f, _) => fractions.add(f),
    );

    expect(result.outputs, hasLength(2));
    expect(File(result.outputs[0].path).lengthSync(), 100000);
    expect(File(result.outputs[1].path).lengthSync(), 200000);
    expect(fractions.last, 1.0);
    expect(tempOut.listSync().whereType<File>().length, 2);
  });

  test('duplicate output names both land, auto-numbered (edge #31)', () async {
    // Two distinct sources that both want the output name "same.txt".
    final a1 = makeInput('src1.txt', [1]);
    final a2 = makeInput('src2.txt', [2]);

    final result = await copyThrough(
      CopyThroughArgs(
        jobs: [(a1, 'same.txt', 1), (a2, 'same.txt', 1)],
        outputDir: tempOut.path,
      ),
    );

    final names = result.outputs.map((o) => o.name).toList();
    expect(names, hasLength(2));
    expect(names.toSet(), hasLength(2));
    final payloads = result.outputs
        .map((o) => File(o.path).readAsBytesSync())
        .toList();
    expect(payloads, containsAll([
      [1],
      [2],
    ]));
  });

  test('ORIGINALS SACRED: inputs byte-identical after processing (F7)', () async {
    final a = makeInput('doc.txt', List.filled(50000, 5));
    final originalBytes = File(a).readAsBytesSync();

    await copyThrough(
      CopyThroughArgs(
        jobs: [(a, 'doc.txt', 50000)],
        outputDir: tempOut.path,
      ),
    );

    expect(File(a).readAsBytesSync(), originalBytes);
  });

  test('unicode names (emoji/Cyrillic) preserved (edge #32)', () async {
    final p = makeInput('doc 📄 отчёт.txt', List.filled(100, 9));
    final result = await copyThrough(
      CopyThroughArgs(jobs: [(p, 'doc 📄 отчёт.txt', 100)], outputDir: tempOut.path),
    );
    expect(result.outputs.single.name, 'doc 📄 отчёт.txt');
  });

  test('cancel from the start throws JobCancelled and writes nothing (edge #50)', () async {
    final a = makeInput('a.txt', List.filled(1, 1));

    await expectLater(
      copyThrough(
        CopyThroughArgs(
          jobs: [(a, 'x.txt', 1)],
          outputDir: tempOut.path,
        ),
        isCancelled: () => true,
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(tempOut.listSync().whereType<File>(), isEmpty);
  });
}
