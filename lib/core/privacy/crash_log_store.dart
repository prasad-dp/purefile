import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One recorded crash (feature 15 privacy dashboard → crash-log viewer).
final class CrashEntry {
  const CrashEntry({required this.at, required this.source, required this.message});

  final DateTime at;

  /// 'flutter' (framework errors) or 'platform' (uncaught zone errors).
  final String source;
  final String message;
}

/// Local ring-buffer crash log. Line format on disk:
/// `<iso8601> <source>: <single-line message>`. Capped at [maxEntries] —
/// the oldest entries fall off. Lives in app-private storage; it never
/// leaves the device (the dashboard explicitly says so).
class CrashLogStore {
  CrashLogStore({File Function()? fileResolver, this.maxEntries = 100})
      : _fileResolver = fileResolver ?? defaultCrashLogFile;

  final File Function() _fileResolver;
  final int maxEntries;

  File get _file => _fileResolver();

  /// Appends one entry. Fire-and-forget safe: never throws, never crashes
  /// because of the crash logger. Multi-line messages are flattened.
  void append(String source, String message) {
    try {
      final file = _file;
      final flat = message.replaceAll('\n', ' / ');
      final line = '${DateTime.now().toIso8601String()} $source: $flat\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: false);
      _trim(file);
    } catch (_) {
      // Last-resort silence.
    }
  }

  /// Loads entries, newest first. Malformed lines are skipped (defensive —
  /// a half-written final line must not take the viewer down).
  Future<List<CrashEntry>> load() async {
    final file = _file;
    if (!file.existsSync()) return const [];
    try {
      final entries = <CrashEntry>[];
      for (final line in file.readAsLinesSync()) {
        final entry = _parse(line);
        if (entry != null) entries.add(entry);
      }
      return entries.reversed.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Removes every recorded crash.
  Future<void> clear() async {
    final file = _file;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------

  /// Rewrites the file with only the newest [maxEntries] lines whenever the
  /// cap is exceeded (a ≤100-line rewrite per crash is negligible; the cap
  /// must hold at all times, not eventually).
  void _trim(File file) {
    final lines = file.readAsLinesSync();
    if (lines.length <= maxEntries) return;
    final keep = lines.sublist(lines.length - maxEntries);
    file.writeAsStringSync('${keep.join('\n')}\n', flush: false);
  }

  CrashEntry? _parse(String line) {
    final space = line.indexOf(' ');
    if (space <= 0) return null;
    final at = DateTime.tryParse(line.substring(0, space));
    if (at == null) return null;
    final rest = line.substring(space + 1);
    final colon = rest.indexOf(': ');
    if (colon <= 0) return null;
    return CrashEntry(
      at: at,
      source: rest.substring(0, colon),
      message: rest.substring(colon + 2),
    );
  }
}

/// Single default log file. Mobile: app-private temp dir; desktop/tests: cwd.
/// The same resolver backs both main() (writers) and Settings (readers).
File defaultCrashLogFile() {
  final dir = (Platform.isAndroid || Platform.isIOS)
      ? Directory.systemTemp
      : Directory.current;
  return File('${dir.path}${Platform.pathSeparator}purefile_crash.log');
}

/// App-wide crash log store.
final crashLogStoreProvider =
    Provider<CrashLogStore>((_) => CrashLogStore());
