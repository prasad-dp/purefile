import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/history/history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

HistoryEntry entry(
  String path, {
  String name = 'out.pdf',
  String toolId = 'pdf_compress',
  int size = 123,
  DateTime? at,
  bool isDirectory = false,
}) =>
    HistoryEntry(
      path: path,
      fileName: name,
      toolId: toolId,
      sizeBytes: size,
      createdAt: at ?? DateTime(2026, 9, 24, 12),
      isDirectory: isDirectory,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('pf_history');
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    temp.deleteSync(recursive: true);
  });

  String makeFile(String name) {
    final f = File('${temp.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    return f.path;
  }

  test('record + load round-trips fields, newest first', () async {
    final p1 = makeFile('a.pdf');
    final p2 = makeFile('b.pdf');
    final store = container.read(historyProvider);

    await store.record(entry(p1, name: 'a.pdf', at: DateTime(2026, 9, 24, 10)));
    await store.record(entry(p2, name: 'b.pdf', at: DateTime(2026, 9, 24, 11)));

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded.first.fileName, 'b.pdf', reason: 'newest first');
    expect(loaded.first.toolId, 'pdf_compress');
    expect(loaded.first.sizeBytes, 123);
    expect(loaded.first.createdAt, DateTime(2026, 9, 24, 11));
  });

  test('re-recording the same path updates instead of duplicating', () async {
    final p = makeFile('a.pdf');
    final store = container.read(historyProvider);
    await store.record(entry(p));
    await store.record(entry(p, name: 'a.pdf', size: 999));

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.sizeBytes, 999);
  });

  test('AUTO-PURGE: records older than retention are dropped (files kept)', () async {
    final p = makeFile('old.pdf');
    final now = DateTime(2026, 9, 24, 12);
    final store = HistoryStore(retention: const Duration(days: 7), clock: () => now);
    await store.record(
          entry(p, at: DateTime(2026, 9, 17, 11)), // 7 days + 1 hour old
        );

    final loaded = await store.load();
    expect(loaded, isEmpty);
    // The record is purged, never the user's file.
    expect(File(p).existsSync(), isTrue);
  });

  test('records within retention survive', () async {
    final p = makeFile('fresh.pdf');
    final store = HistoryStore(retention: const Duration(days: 7));
    await store.record(entry(p, at: DateTime.now()));

    expect(await store.load(), hasLength(1));
  });

  test('ORPHAN CLEANUP: records whose backing file vanished are dropped', () async {
    final store = container.read(historyProvider);
    final real = makeFile('real.pdf');
    await store.record(entry(real, name: 'real.pdf'));
    await store.record(entry('${temp.path}${Platform.pathSeparator}ghost.pdf',
        name: 'ghost.pdf'));

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.fileName, 'real.pdf');
  });

  test('directory entries (zip extract) load when the folder exists', () async {
    final dir = Directory('${temp.path}${Platform.pathSeparator}report')
      ..createSync();
    final store = container.read(historyProvider);
    await store.record(entry(dir.path, name: 'report', isDirectory: true));

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.isDirectory, isTrue);
  });

  test('clear removes records only — files stay on disk', () async {
    final p = makeFile('a.pdf');
    final store = container.read(historyProvider);
    await store.record(entry(p));
    await store.clear();

    expect(await store.load(), isEmpty);
    expect(File(p).existsSync(), isTrue);
  });

  test('remove drops one record and keeps the file', () async {
    final p1 = makeFile('a.pdf');
    final p2 = makeFile('b.pdf');
    final store = container.read(historyProvider);
    await store.record(entry(p1, name: 'a.pdf'));
    await store.record(entry(p2, name: 'b.pdf'));
    await store.remove(p1);

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.fileName, 'b.pdf');
    expect(File(p1).existsSync(), isTrue);
  });

  test('CAP: history is capped at maxEntries, oldest dropped', () async {
    final store = HistoryStore(maxEntries: 5);
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      final p = makeFile('f$i.pdf');
      await store.record(entry(p, name: 'f$i.pdf',
          at: now.subtract(Duration(minutes: 100 - i))));
    }
    final loaded = await store.load();
    expect(loaded, hasLength(5));
    expect(loaded.first.fileName, 'f7.pdf', reason: 'newest kept first');
    expect(loaded.last.fileName, 'f3.pdf', reason: 'oldest fell off');
  });

  test('corrupted stored JSON loads as empty instead of crashing', () async {
    SharedPreferences.setMockInitialValues({'pf.history.v1': 'not-json{['});
    final store = container.read(historyProvider);
    expect(await store.load(), isEmpty);
  });
}
