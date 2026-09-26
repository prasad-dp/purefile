import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One processed output in the local history (feature 10). Files live in the
/// app's outputs directory; history rows are just pointers + metadata.
final class HistoryEntry {
  const HistoryEntry({
    required this.path,
    required this.fileName,
    required this.toolId,
    required this.sizeBytes,
    required this.createdAt,
    this.isDirectory = false,
    this.fileExists = true,
  });

  /// Absolute path of the output (file — or folder for zip-extract results).
  final String path;
  final String fileName;

  /// Tool registry id that produced this output (e.g. `pdf_compress`).
  final String toolId;
  final int sizeBytes;
  final DateTime createdAt;

  /// True for zip-extract results, which produce a folder, not a file.
  final bool isDirectory;

  /// False when the backing file was removed (purge, user cleanup, or a
  /// factory reset of the outputs directory). Such rows drop on next load.
  final bool fileExists;

  HistoryEntry withFileExists(bool exists) => HistoryEntry(
        path: path,
        fileName: fileName,
        toolId: toolId,
        sizeBytes: sizeBytes,
        createdAt: createdAt,
        isDirectory: isDirectory,
        fileExists: exists,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'name': fileName,
        'toolId': toolId,
        'size': sizeBytes,
        'at': createdAt.millisecondsSinceEpoch,
        if (isDirectory) 'dir': true,
      };

  static HistoryEntry fromJson(Map<String, Object?> json) {
    final at = (json['at'] as num?)?.toInt() ?? 0;
    return HistoryEntry(
      path: (json['path'] as String?) ?? '',
      fileName: (json['name'] as String?) ?? '',
      toolId: (json['toolId'] as String?) ?? 'unknown',
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
      isDirectory: (json['dir'] as bool?) ?? false,
    );
  }
}

/// Local-only history (no cloud, no internet — F10). Stored in
/// SharedPreferences as one JSON list; rows older than [retention] days are
/// dropped on load (auto-purge), rows whose backing file vanished are dropped
/// too (orphan cleanup), and the list is capped at [maxEntries].
///
/// Never deletes user files: purge removes *records* only; the outputs
/// directory itself is managed separately (settings / storage, F15).
/// App-wide store instance (records live in SharedPreferences).
final historyProvider = Provider<HistoryStore>((_) => HistoryStore());

class HistoryStore {
  HistoryStore({
    this.retention = const Duration(days: 7),
    this.maxEntries = 400,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _key = 'pf.history.v1';

  final Duration retention;
  final int maxEntries;
  final DateTime Function() _clock;

  /// Records one finished output. Returns the stored entry.
  Future<HistoryEntry> record(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _decode(prefs.getString(_key))
        .where((e) => e.path != entry.path)
        .toList();
    entries.insert(0, entry.withFileExists(_exists(entry)));
    await prefs.setString(_key, jsonEncode(_compact(entries).map(_toJson).toList()));
    return entries.first;
  }

  /// Loads entries: newest first, auto-purged by age, orphans dropped.
  Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();
    final alive = <HistoryEntry>[];
    for (final e in _decode(prefs.getString(_key))) {
      final age = now.difference(e.createdAt);
      if (age > retention) continue; // auto-purge: record only, never the file
      if (!_exists(e)) continue; // orphan: backing file is gone
      alive.add(e.withFileExists(true));
    }
    if (alive.length != _decode(prefs.getString(_key)).length) {
      await prefs.setString(_key, jsonEncode(_compact(alive).map(_toJson).toList()));
    }
    return _compact(alive);
  }

  /// Removes every record (Clear all). Files stay on disk.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Removes one record. The backing file stays on disk.
  Future<void> remove(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final entries =
        _decode(prefs.getString(_key)).where((e) => e.path != path).toList();
    await prefs.setString(_key, jsonEncode(entries.map(_toJson).toList()));
  }

  // -------------------------------------------------------------------------

  List<HistoryEntry> _compact(List<HistoryEntry> entries) {
    final sorted = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(maxEntries).toList();
  }

  Map<String, Object?> _toJson(HistoryEntry e) => e.toJson();

  bool _exists(HistoryEntry e) =>
      e.path.isNotEmpty &&
      (e.isDirectory ? Directory(e.path).existsSync() : File(e.path).existsSync());

  List<HistoryEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, Object?>) HistoryEntry.fromJson(item),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }
}
