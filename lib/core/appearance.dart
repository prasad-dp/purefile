import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance (theme mode) controller — the light/dark mode feature.
///
/// Single source of truth: [themeModeProvider] holds the live [ThemeMode];
/// MaterialApp watches it. The user's choice persists under
/// `pf.appearance.mode` ("system" | "light" | "dark"); an unknown stored
/// value falls back to system instead of crashing.
///
/// Persistence is behind [AppearancePersistence] so tests can inject a fake
/// via [appearancePersistenceProvider] (same seam style as VaultKeyStorage).
abstract class AppearancePersistence {
  Future<String?> load();
  Future<void> save(String mode);
}

final class SharedPreferencesAppearance implements AppearancePersistence {
  static const _key = 'pf.appearance.mode';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode);
  }
}

/// Overridable in tests.
final appearancePersistenceProvider = Provider<AppearancePersistence>(
  (ref) => SharedPreferencesAppearance(),
);

ThemeMode? _parse(String? raw) => switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };

/// The quick-toggle rule (home hero button): tap always lands on the
/// OPPOSITE brightness — one tap light ⇄ dark from anywhere. In system mode
/// the target is based on the ACTIVE platform brightness (auto-in-daylight →
/// tap = dark). Explicit light/dark always just flips. Auto itself is only
/// selectable from the Settings segmented control.
ThemeMode toggleThemeMode(ThemeMode current, Brightness platformBrightness) {
  final activeIsLight = current == ThemeMode.light ||
      (current == ThemeMode.system && platformBrightness == Brightness.light);
  return activeIsLight ? ThemeMode.dark : ThemeMode.light;
}

/// The live theme mode. Read by MaterialApp; writes go through
/// [AppearanceController.setMode] which also persists.
final themeModeProvider =
    NotifierProvider<AppearanceController, ThemeMode>(
        AppearanceController.new);

/// Completes once the persisted choice has been loaded into
/// [themeModeProvider]. The app root awaits this before the first frame so a
/// dark-mode user never sees a light flash at launch.
final appearanceReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(themeModeProvider.notifier).restore(),
);

class AppearanceController extends Notifier<ThemeMode> {
  AppearancePersistence? _persistence;
  Future<void>? _restoring;

  @override
  ThemeMode build() => ThemeMode.system;

  /// Lazily resolved once — setMode must persist even if restore() never ran
  /// (e.g. the user toggles before the startup restore completes).
  AppearancePersistence get _store {
    _persistence ??= ref.read(appearancePersistenceProvider);
    return _persistence!;
  }

  /// One-time restore from persistence. Repeated calls reuse the first load;
  /// a storage failure leaves system mode (best-effort, never fatal).
  Future<void> restore() {
    return _restoring ??= () async {
      String? stored;
      try {
        stored = await _store.load();
      } catch (_) {
        return; // unreadable storage → keep system mode
      }
      final parsed = _parse(stored);
      if (parsed != null) state = parsed;
    }();
  }

  /// Sets the mode and persists it. A persistence failure never breaks the
  /// UI — the in-session choice still applies; it just won't survive restart.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _store.save(mode.name);
    } catch (_) {
      // Local-only preference: storage problems stay silent.
    }
  }
}
