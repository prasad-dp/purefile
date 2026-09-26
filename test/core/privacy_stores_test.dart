import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/privacy/crash_log_store.dart';
import 'package:purefile/core/privacy/usage_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('usage store', () {
    test('apply processes events and load reflects them', () async {
      final store = UsageStore();
      await store.apply(const UsageProcessed(
          toolId: 'pdf_compress', count: 1, bytes: 1234));
      await store.apply(const UsageProcessed(
          toolId: 'pdf_compress', count: 2, bytes: 2000));
      await store.apply(const UsageVaulted(count: 3, bytes: 300));

      final stats = await store.load();
      expect(stats.processedCount, 3);
      expect(stats.processedBytes, 3234);
      expect(stats.vaultedCount, 3);
      expect(stats.vaultedBytes, 300);
      expect(stats.totalCount, 6);
      expect(stats.totalBytes, 3534);
      expect(stats.perTool['pdf_compress'], 3);
      expect(stats.lastActivity, isNotNull);
    });

    test('toolsByCount sorts by count then id', () async {
      final store = UsageStore();
      await store.apply(
          const UsageProcessed(toolId: 'b_tool', count: 1, bytes: 10));
      await store.apply(
          const UsageProcessed(toolId: 'a_tool', count: 5, bytes: 10));
      await store.apply(
          const UsageProcessed(toolId: 'c_tool', count: 5, bytes: 10));

      final stats = await store.load();
      expect(
        stats.toolsByCount().map((e) => e.key).toList(),
        ['a_tool', 'c_tool', 'b_tool'],
      );
    });

    test('reset returns everything to zero', () async {
      final store = UsageStore();
      await store.apply(
          const UsageProcessed(toolId: 'x', count: 7, bytes: 700));
      await store.reset();
      final stats = await store.load();
      expect(stats.totalCount, 0);
      expect(stats.totalBytes, 0);
      expect(stats.perTool, isEmpty);
      expect(stats.lastActivity, isNull);
    });

    test('concurrent applies serialize without losing updates', () async {
      final store = UsageStore();
      await Future.wait([
        for (var i = 0; i < 20; i++)
          store.apply(const UsageProcessed(toolId: 't', count: 1, bytes: 1)),
      ]);
      final stats = await store.load();
      expect(stats.processedCount, 20, reason: 'no lost updates');
    });

    test('lastActivity uses the injected clock', () async {
      var fake = DateTime(2026, 9, 25, 12);
      final store = UsageStore(clock: () => fake);
      await store.apply(const UsageProcessed(toolId: 't', count: 1, bytes: 1));
      fake = fake.add(const Duration(hours: 2));
      await store.apply(const UsageProcessed(toolId: 't', count: 1, bytes: 1));
      final stats = await store.load();
      expect(stats.lastActivity, fake);
    });
  });

  group('crash log store', () {
    late Directory dir;
    late CrashLogStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pf_crash_test');
      store = CrashLogStore(
          fileResolver: () =>
              File('${dir.path}${Platform.pathSeparator}crash.log'));
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('append + load round-trip, newest first', () async {
      store.append('flutter', 'Boom one');
      store.append('platform', 'Boom two');
      final entries = await store.load();
      expect(entries, hasLength(2));
      expect(entries.first.message, 'Boom two');
      expect(entries.first.source, 'platform');
      expect(entries.last.message, 'Boom one');
    });

    test('multi-line messages are flattened', () async {
      store.append('flutter', 'line one\nline two\nline three');
      final entries = await store.load();
      expect(entries.single.message, 'line one / line two / line three');
    });

    test('clear removes the file', () async {
      store.append('flutter', 'gone soon');
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('cap holds: oldest entries fall off', () async {
      final small = CrashLogStore(
          fileResolver: () =>
              File('${dir.path}${Platform.pathSeparator}small.log'),
          maxEntries: 5);
      for (var i = 0; i < 40; i++) {
        small.append('flutter', 'crash $i');
      }
      final entries = await small.load();
      expect(entries.length, 5);
      expect(entries.first.message, 'crash 39');
    });

    test('malformed lines are skipped, not fatal', () async {
      final file = File('${dir.path}${Platform.pathSeparator}crash.log');
      file.writeAsStringSync('not a valid line\n'
          '2026-09-25T10:00:00.000 flutter: real entry\n'
          '2026-99-99T99: garbage date\n');
      final entries = await store.load();
      expect(entries, hasLength(1));
      expect(entries.single.message, 'real entry');
    });

    test('load on a missing file is empty', () async {
      expect(await store.load(), isEmpty);
    });
  });
}
