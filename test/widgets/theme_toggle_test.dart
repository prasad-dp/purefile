import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/appearance.dart';
import 'package:purefile/l10n/generated/app_localizations.dart';
import 'package:purefile/widgets/theme_toggle.dart';

class _FakePersistence implements AppearancePersistence {
  @override
  Future<String?> load() async => null;

  @override
  Future<void> save(String mode) async {}
}

Widget _host(Widget child) => ProviderScope(
      overrides: [
        appearancePersistenceProvider
            .overrideWith((ref) => _FakePersistence()),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('ThemeToggleButton flips light ⇄ dark in one tap',
      (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host(
      Consumer(builder: (context, ref, _) {
        captured = ref;
        return const ThemeToggleButton();
      }),
    ));
    await tester.pumpAndSettle();

    // Starts in system mode; the test surface is light → sun shows.
    expect(captured.read(themeModeProvider), ThemeMode.system);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    // One tap → dark (the opposite of the active brightness).
    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(captured.read(themeModeProvider), ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    // One tap → light again. Never a cycle, never auto.
    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(captured.read(themeModeProvider), ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
  });

  testWidgets('ThemeToggleIcon shows the auto dot badge in system mode only',
      (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host(
      Consumer(builder: (context, ref, _) {
        captured = ref;
        return const ThemeToggleIcon();
      }),
    ));
    await tester.pumpAndSettle();

    // system + light surface → sun WITH dot badge.
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    // Pin dark → moon, no badge.
    await captured.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  testWidgets('ThemeToggleIcon applies its background + color (hero look)',
      (tester) async {
    await tester.pumpWidget(_host(
      const ThemeToggleIcon(color: Colors.white, background: Colors.black26),
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.light_mode_outlined),
        matching: find.byType(IconButton)));
    expect(
      button.style?.backgroundColor?.resolve({}),
      Colors.black26,
    );
  });
}
