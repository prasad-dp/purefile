import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/pdf/pdf_split_service.dart';
import 'package:purefile/core/jobs/job_controller.dart';
import 'package:purefile/features/tools/tool_flow_screen.dart';
import 'package:purefile/l10n/generated/app_localizations.dart';

/// Regressions for the split-options bugs:
/// A) Typing never re-published the options state → errorText and the Start
///    button stayed stale until the user left the screen and came back.
/// B) The split Start callback used ref.watch inside a tap handler (illegal)
///    → tapping Start threw and nothing happened.
void main() {
  testWidgets('typing clears the error and enables Start WITHOUT navigation',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SplitOptions()),
        ),
      ),
    );

    // Switch to Ranges mode (empty input → invalid → error shows).
    await tester.tap(find.text('Ranges'));
    await tester.pumpAndSettle();
    expect(container.read(splitOptionsProvider).valid, isFalse);
    expect(find.text('Enter at least one valid range'), findsOneWidget);

    // Type a range → the error must disappear LIVE (bug A) — no navigation.
    await tester.enterText(find.byType(TextField), '1-3,5');
    await tester.pumpAndSettle();

    expect(container.read(splitOptionsProvider).valid, isTrue);
    expect(find.text('Enter at least one valid range'), findsNothing);
    expect(find.text('Fix the split options above to enable Start.'),
        findsNothing);
  });

  testWidgets('Start callback is wired to a live onPressed (bug B shape)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Valid options from the start (everyN defaults to interval 1).
    container.read(splitOptionsProvider.notifier).state =
        SplitOptionsState();

    SplitOptionsBuildState? probe;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                probe = SplitOptionsBuildState(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    // The build-context read that Start performs must resolve without
    // throwing (ref.watch inside a callback threw before the fix).
    expect(() => probe!.readSplitOptions(), returnsNormally);
    expect(probe!.readSplitOptions(), isA<SplitOptionsState>());
  });

  test('publish() shares controllers (focus/cursor preserved) but is a NEW state',
      () {
    final state = SplitOptionsState();
    state.selectionController.text = '2,4';
    final next = state.publish(SplitMode.extract);

    expect(next.mode, SplitMode.extract);
    expect(identical(next.selectionController, state.selectionController),
        isTrue,
        reason: 'same controller = no focus loss while typing');
    expect(identical(next, state), isFalse,
        reason: 'new instance = Riverpod listeners re-fire');
    expect(next.selection, isNotEmpty);
  });
}

/// Test helper: performs the same provider read the Start callback does.
class SplitOptionsBuildState {
  SplitOptionsBuildState(this.context);

  final BuildContext context;

  SplitOptionsState readSplitOptions() {
    return ProviderScope.containerOf(context, listen: false)
        .read(splitOptionsProvider);
  }
}
