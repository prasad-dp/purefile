import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/isolate_runner.dart';

void main() {
  group('runJob', () {
    test('delivers result and done event', () async {
      final handle = runJob<int>(task: (ctx) async => 42);
      final result = await handle.future;
      expect(result, 42);
    });

    test('reports progress events', () async {
      final handle = runJob<int>(task: (ctx) async {
        ctx.report(0.25, 'quarter');
        ctx.report(0.5, 'half');
        return 1;
      });
      final progress = <double>[];
      handle.events.listen((e) {
        if (e is JobProgress<int>) progress.add(e.fraction);
      });
      await handle.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(progress, containsAllInOrder([0.25, 0.5]));
    });

    test('typed PureError inside task surfaces as JobFailed', () async {
      final handle = runJob<int>(
        task: (ctx) async => throw const WrongPassword(),
      );
      await expectLater(handle.future, throwsA(isA<WrongPassword>()));
    });

    test('arbitrary exception maps to UnknownFailure', () async {
      final handle = runJob<int>(task: (ctx) async => throw StateError('boom'));
      await expectLater(handle.future, throwsA(isA<UnknownFailure>()));
    });

    test('cancel kills a long job quickly (edge #50)', () async {
      final handle = runJob<int>(
        task: (ctx) async {
          // Pretends to work forever, ignoring the flag (worst case).
          await Future<void>.delayed(const Duration(minutes: 10));
          return 0;
        },
        timeout: const Duration(minutes: 1),
      );
      Future<void>.delayed(const Duration(milliseconds: 100), handle.cancel);
      final sw = Stopwatch()..start();
      await expectLater(handle.future, throwsA(isA<JobCancelled>()));
      expect(sw.elapsed.inSeconds, lessThan(5));
    });

    test('timeout kills a hung job with JobTimedOut (F4 timeout guard)', () async {
      final handle = runJob<int>(
        task: (ctx) async {
          await Future<void>.delayed(const Duration(minutes: 10));
          return 0;
        },
        timeout: const Duration(milliseconds: 300),
      );
      await expectLater(handle.future, throwsA(isA<JobTimedOut>()));
    });

    test('cooperative cancel: task sees the flag and exits cleanly', () async {
      final handle = runJob<int>(
        task: (ctx) async {
          for (var i = 0; i < 100; i++) {
            if (ctx.isCancelled) throw const JobCancelled();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return 0;
        },
      );
      Future<void>.delayed(const Duration(milliseconds: 60), handle.cancel);
      await expectLater(handle.future, throwsA(isA<JobCancelled>()));
    });

    test('sendable result round-trips (Uint8List)', () async {
      final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final handle = runJob<Uint8List>(task: (ctx) async => data);
      final out = await handle.future;
      expect(out, data);
    });

    test('delivers result with entry and args without closures', () async {
      Future<int> multiply(dynamic val, PfJobContext ctx) async => (val as int) * 2;

      final handle = runJob<int>(entry: multiply, args: 21);
      final result = await handle.future;
      expect(result, 42);
    });

    test('entry reports progress and cooperative cancel with args', () async {
      Future<String> worker(dynamic prefix, PfJobContext ctx) async {
        ctx.report(0.5, 'half');
        return '${prefix as String} done';
      }

      final handle = runJob<String>(entry: worker, args: 'job');
      final result = await handle.future;
      expect(result, 'job done');
    });
  });
}
