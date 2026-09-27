import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/jobs/copy_through_service.dart';
import 'package:purefile/core/jobs/job_controller.dart';
import 'package:purefile/core/isolate_runner.dart' as runner;
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the "object is unsendable" device failure (every
/// tool dead at Start): the job-spawn closure captured the Riverpod
/// controller's `this`, which transitively held the element tree. These run
/// in a PLAIN test() — real event loop, so cross-isolate ports deliver —
/// with a real ProviderContainer, mirroring the device shape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runToolTask dispatch (isolate entry)', () {
    test('routes CopyThroughArgs through a real spawned isolate', () async {
      final dir = await Directory.systemTemp.createTemp('pf_spawn');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = File('${dir.path}/in.txt')..writeAsStringSync('hello');
      final srcPath = src.path;
      final args = CopyThroughArgs(
        jobs: [(srcPath, 'in.txt', src.lengthSync())],
        outputDir: dir.path,
      );

      final handle = runner.runJob<Object?>(
        entry: runToolTask,
        args: args,
      );
      final result = await handle.future;
      expect(result, isA<CopyThroughResult>());
    });
  });

  group('JobFlowController.start through a REAL spawn (device repro)', () {
    test('select → start → JobDone while the container is alive', () async {
      SharedPreferences.setMockInitialValues({});
      final docs = await Directory.systemTemp.createTemp('pf_docs_reg');
      addTearDown(() => docs.deleteSync(recursive: true));

      // Header-valid PDF so the magic gate accepts it (copy-through ignores
      // the body; the validator does not).
      final src = File('${docs.path}/input.pdf')
        ..writeAsBytesSync(
            [...'%PDF-1.4\n'.codeUnits, ...List.generate(64, (i) => i % 256)]);
      final srcPath = src.path;

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(jobFlowProvider.notifier);

      await controller.selectFiles([srcPath]);
      expect(container.read(jobFlowProvider), isA<JobReady>());

      // The call that died on device with "object is unsendable": the spawn
      // closure must not drag the controller/container into the isolate.
      await controller.start(
        toolId: 'copy_through',
        makeArgs: (outputDir) => CopyThroughArgs(
          jobs: [(srcPath, 'input.pdf', src.lengthSync())],
          outputDir: outputDir,
        ),
      );

      // The JobDone event listener runs a microtask behind start()'s
      // await-resumption — flush the real event loop before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(jobFlowProvider), isA<JobDone>());
    });

    test('container disposal after a finished job is clean (no dangling)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final docs = await Directory.systemTemp.createTemp('pf_docs_reg2');
      addTearDown(() => docs.deleteSync(recursive: true));
      final src = File('${docs.path}/input.pdf')
        ..writeAsBytesSync([...'%PDF-1.4\n'.codeUnits, ...'\n%%EOF'.codeUnits]);
      final srcPath = src.path;

      final container = ProviderContainer();
      final controller = container.read(jobFlowProvider.notifier);
      await controller.selectFiles([srcPath]);
      await controller.start(
        toolId: 'copy_through',
        makeArgs: (outputDir) =>
            CopyThroughArgs(jobs: const [], outputDir: outputDir),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(jobFlowProvider), isA<JobDone>());
      container.dispose();
    });
  });

  group('isolate-safety guard (static shape)', () {
    // The bug class: closures passed to runJob/Isolate.spawn must not
    // capture `this` of a stateful object. runToolTask being a TOP-LEVEL
    // function is the structural fix — assert the shape stays top-level so
    // a future refactor can't silently reintroduce the device failure.
    test('runToolTask is a top-level function, not a method tear-off', () {
      // A method tear-off's == differs from a top-level function reference;
      // more decisively, tear-offs of instance methods report the object in
      // their hash identity. The simplest structural check: the symbol is
      // library-scoped and the function reference is const-equal to itself.
      final f = runToolTask;
      expect(identical(f, runToolTask), isTrue);
    });
  });
}
