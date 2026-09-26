import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch shows onboarding, then home renders tool grid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: PureFileApp()));
    await tester.pumpAndSettle();

    // Onboarding slide 1.
    expect(find.text('One toolbox for your files'), findsOneWidget);

    // Walk to the end and finish.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Home renders all sections and the privacy badge.
    expect(find.text('PureFile'), findsOneWidget);
    expect(find.text('Compress PDF'), findsOneWidget);
    expect(
      find.text('100% offline — your files never leave this phone'),
      findsOneWidget,
    );

    // The Vault section sits below the fold — scroll to it.
    await tester.scrollUntilVisible(
      find.text('Private Vault'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Vault'), findsOneWidget);
  });

  testWidgets('search filters tools', (tester) async {
    SharedPreferences.setMockInitialValues({'pf_onboarding_done': true});
    await tester.pumpWidget(const ProviderScope(child: PureFileApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'vault');
    await tester.pumpAndSettle();

    expect(find.text('Private Vault'), findsOneWidget);
    expect(find.text('Compress PDF'), findsNothing);
  });
}
