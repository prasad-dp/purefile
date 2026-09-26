import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One atomic mutation of the usage counters (feature 15 privacy dashboard).
sealed class UsageEvent {
  const UsageEvent();
}

/// A tool finished with [count] outputs totalling [bytes] processed.
final class UsageProcessed extends UsageEvent {
  const UsageProcessed({
    required this.toolId,
    required this.count,
    required this.bytes,
  });

  final String toolId;
  final int count;
  final int bytes;
}

/// Files went into the vault ([count] files, [bytes] encrypted).
final class UsageVaulted extends UsageEvent {
  const UsageVaulted({required this.count, required this.bytes});

  final int count;
  final int bytes;
}

/// Snapshotted counters for the privacy dashboard.
final class UsageStats {
  const UsageStats({
    this.processedCount = 0,
    this.processedBytes = 0,
    this.vaultedCount = 0,
    this.vaultedBytes = 0,
    this.perTool = const {},
    this.lastActivity,
  });

  final int processedCount;
  final int processedBytes;
  final int vaultedCount;
  final int vaultedBytes;

  /// toolId → output count (dashboard top list).
  final Map<String, int> perTool;

  final DateTime? lastActivity;

  int get totalCount => processedCount + vaultedCount;
  int get totalBytes => processedBytes + vaultedBytes;

  /// Highest-count tools first, ties broken by toolId for stable UI.
  List<MapEntry<String, int>> toolsByCount() {
    final entries = perTool.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }
}

/// SharedPreferences-backed counters (never leaves the device — same story as
/// the F10 history store). All mutations are serialized through one async
/// queue so concurrent job completions can't lose updates; tests use
/// SharedPreferences.setMockInitialValues like the history tests do.
class UsageStore {
  UsageStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _kProcessedCount = 'pf.usage.processed.count';
  static const _kProcessedBytes = 'pf.usage.processed.bytes';
  static const _kVaultedCount = 'pf.usage.vaulted.count';
  static const _kVaultedBytes = 'pf.usage.vaulted.bytes';
  static const _kPerToolPrefix = 'pf.usage.tool.';
  static const _kLastAt = 'pf.usage.last.millis';

  final DateTime Function() _clock;

  Future<void> _queue = Future.value();

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action(), onError: (_) => action());
  }

  /// Applies one event atomically (stats are immutable — copy-on-write).
  Future<void> apply(UsageEvent event) {
    _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final s = _load(prefs);
      final now = _clock();
      final updated = switch (event) {
        UsageProcessed(:final toolId, :final count, :final bytes) => UsageStats(
            processedCount: s.processedCount + count,
            processedBytes: s.processedBytes + bytes,
            vaultedCount: s.vaultedCount,
            vaultedBytes: s.vaultedBytes,
            perTool: {...s.perTool, toolId: (s.perTool[toolId] ?? 0) + count},
            lastActivity: now,
          ),
        UsageVaulted(:final count, :final bytes) => UsageStats(
            processedCount: s.processedCount,
            processedBytes: s.processedBytes,
            vaultedCount: s.vaultedCount + count,
            vaultedBytes: s.vaultedBytes + bytes,
            perTool: s.perTool,
            lastActivity: now,
          ),
      };
      await _save(prefs, updated);
    });
    return _queue;
  }

  Future<UsageStats> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _load(prefs);
  }

  /// Wipes every counter (dashboard reset button).
  Future<void> reset() {
    _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kProcessedCount);
      await prefs.remove(_kProcessedBytes);
      await prefs.remove(_kVaultedCount);
      await prefs.remove(_kVaultedBytes);
      await prefs.remove(_kLastAt);
      for (final k in prefs
          .getKeys()
          .where((k) => k.startsWith(_kPerToolPrefix))
          .toList()) {
        await prefs.remove(k);
      }
    });
    return _queue;
  }

  // ---------------------------------------------------------------------------

  UsageStats _load(SharedPreferences prefs) {
    final lastAt = prefs.getInt(_kLastAt);
    return UsageStats(
      processedCount: prefs.getInt(_kProcessedCount) ?? 0,
      processedBytes: prefs.getInt(_kProcessedBytes) ?? 0,
      vaultedCount: prefs.getInt(_kVaultedCount) ?? 0,
      vaultedBytes: prefs.getInt(_kVaultedBytes) ?? 0,
      perTool: {
        for (final k in prefs
            .getKeys()
            .where((k) => k.startsWith(_kPerToolPrefix)))
          k.substring(_kPerToolPrefix.length): prefs.getInt(k) ?? 0,
      },
      lastActivity:
          lastAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAt),
    );
  }

  Future<void> _save(SharedPreferences prefs, UsageStats s) async {
    await prefs.setInt(_kProcessedCount, s.processedCount);
    await prefs.setInt(_kProcessedBytes, s.processedBytes);
    await prefs.setInt(_kVaultedCount, s.vaultedCount);
    await prefs.setInt(_kVaultedBytes, s.vaultedBytes);
    await prefs.setInt(_kLastAt, _clock().millisecondsSinceEpoch);
    for (final entry in s.perTool.entries) {
      await prefs.setInt('$_kPerToolPrefix${entry.key}', entry.value);
    }
  }
}

/// App-wide usage store.
final usageStoreProvider = Provider<UsageStore>((_) => UsageStore());

/// Dashboard-facing snapshot, refreshed after job/vault mutations.
final usageStatsProvider = AsyncNotifierProvider<UsageStatsController, UsageStats>(
    UsageStatsController.new);

class UsageStatsController extends AsyncNotifier<UsageStats> {
  @override
  Future<UsageStats> build() => ref.read(usageStoreProvider).load();

  /// Re-reads counters after a job/vault mutation.
  Future<void> refresh() async {
    state = AsyncData(await ref.read(usageStoreProvider).load());
  }

  Future<void> resetAll() async {
    await ref.read(usageStoreProvider).reset();
    state = const AsyncData(UsageStats());
  }
}
