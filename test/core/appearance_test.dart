import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake persistence: records writes, serves scripted reads.
class _FakePersistence implements AppearancePersistence {
  _FakePersistence([this._stored]);

  String? _stored;
  final List<String> saved = [];

  @override
  Future<String?> load() async => _stored;

  @override
  Future<void> save(String mode) {
    _stored = mode;
    saved.add(mode);
    return Future.value();
  }
}

ProviderContainer _container(_FakePersistence persistence) =>
    ProviderContainer(
      overrides: [appearancePersistenceProvider.overrideWithValue(persistence)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppearanceController', () {
    test('defaults to system mode', () {
      final c = _container(_FakePersistence());
      addTearDown(c.dispose);
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('restore() applies the persisted dark mode', () async {
      final c = _container(_FakePersistence('dark'));
      addTearDown(c.dispose);
      await c.read(appearanceReadyProvider.future);
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    test('restore() applies persisted light mode', () async {
      final c = _container(_FakePersistence('light'));
      addTearDown(c.dispose);
      await c.read(appearanceReadyProvider.future);
      expect(c.read(themeModeProvider), ThemeMode.light);
    });

    test('restore() keeps system for missing and unknown values', () async {
      for (final stored in [null, 'bogus', '']) {
        final c = _container(_FakePersistence(stored));
        addTearDown(c.dispose);
        await c.read(appearanceReadyProvider.future);
        expect(c.read(themeModeProvider), ThemeMode.system,
            reason: 'stored=$stored');
      }
    });

    test('setMode persists and updates state', () async {
      final fake = _FakePersistence();
      final c = _container(fake);
      addTearDown(c.dispose);

      await c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(fake.saved, ['dark']);
    });

    test('storage failure does not break the in-session choice', () async {
      final c = ProviderContainer(overrides: [
        appearancePersistenceProvider
            .overrideWith((ref) => _ThrowingPersistence()),
      ]);
      addTearDown(c.dispose);

      await c.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      expect(c.read(themeModeProvider), ThemeMode.light);
    });

    test('restore survives a storage failure (system mode)', () async {
      final c = ProviderContainer(overrides: [
        appearancePersistenceProvider
            .overrideWith((ref) => _ThrowingPersistence()),
      ]);
      addTearDown(c.dispose);
      await c.read(appearanceReadyProvider.future);
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('restore is idempotent (second call reuses first load)', () async {
      final fake = _FakePersistence('dark');
      final c = _container(fake);
      addTearDown(c.dispose);
      final notifier = c.read(themeModeProvider.notifier);
      await notifier.restore();
      await notifier.restore();
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('toggleThemeMode (direct light ⇄ dark)', () {
    test('explicit light → dark, explicit dark → light', () {
      expect(toggleThemeMode(ThemeMode.light, Brightness.light),
          ThemeMode.dark);
      expect(toggleThemeMode(ThemeMode.dark, Brightness.light),
          ThemeMode.light);
      expect(toggleThemeMode(ThemeMode.dark, Brightness.dark),
          ThemeMode.light);
      expect(toggleThemeMode(ThemeMode.light, Brightness.dark),
          ThemeMode.dark);
    });

    test('system follows the ACTIVE platform brightness', () {
      expect(toggleThemeMode(ThemeMode.system, Brightness.light),
          ThemeMode.dark);
      expect(toggleThemeMode(ThemeMode.system, Brightness.dark),
          ThemeMode.light);
    });

    test('never returns system — auto only via Settings', () {
      for (final mode in ThemeMode.values) {
        for (final b in Brightness.values) {
          expect(toggleThemeMode(mode, b), isNot(ThemeMode.system));
        }
      }
    });
  });

  group('persistence key round-trip', () {
    test('SharedPreferences round-trips the chosen mode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pf.appearance.mode', ThemeMode.dark.name);
      expect(prefs.getString('pf.appearance.mode'), 'dark');
    });
  });
}

class _ThrowingPersistence implements AppearancePersistence {
  @override
  Future<String?> load() async => throw StateError('storage unavailable');

  @override
  Future<void> save(String mode) async => throw StateError('storage unavailable');
}
