import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/history/history_store.dart';
import 'package:purefile/features/history/history_screen.dart';
import 'package:purefile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('pf_history_ui');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('empty store shows the empty state', (tester) async {
    await _pump(tester);
    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('appear here'), findsOneWidget);
  });

  testWidgets('records render as rows with file name and tool title', (tester) async {
    final f = File('${temp.path}${Platform.pathSeparator}report.pdf');
    f.writeAsBytesSync([1, 2, 3]);
    final store = HistoryStore();
    await store.record(HistoryEntry(
      path: f.path,
      fileName: 'report.pdf',
      toolId: 'pdf_compress',
      sizeBytes: 3,
      createdAt: DateTime.now(),
    ));

    await _pump(tester);

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('Compress PDF'), findsOneWidget);
  });

  testWidgets('clear all (confirmed) empties the list', (tester) async {
    final f = File('${temp.path}${Platform.pathSeparator}report.pdf');
    f.writeAsBytesSync([1, 2, 3]);
    final store = HistoryStore();
    await store.record(HistoryEntry(
      path: f.path,
      fileName: 'report.pdf',
      toolId: 'pdf_compress',
      sizeBytes: 3,
      createdAt: DateTime.now(),
    ));

    await _pump(tester);
    expect(find.byType(ListTile), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    // The file itself survives — records only.
    expect(f.existsSync(), isTrue);
  });
}
