import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/jobs/job_controller.dart';
import 'package:purefile/core/tools.dart';
import 'package:purefile/features/tools/tool_flow_screen.dart';
import 'package:purefile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressions for two device-reported selection bugs:
/// 1. A JobReady from one tool (Merge) appeared inside another (Split) —
///    the app-scoped flow state was never reset on tool entry.
/// 2. "Add more files" REPLACED the selection instead of appending (merge
///    stayed at 1 file, Start disabled by minFiles: 2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late String pdfPath;
  late String pdfPath2;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    docs = await Directory.systemTemp.createTemp('pf_selection');
    pdfPath = '${docs.path}/a.pdf';
    pdfPath2 = '${docs.path}/b.pdf';
    for (final p in [pdfPath, pdfPath2]) {
      File(p).writeAsBytesSync([...'%PDF-1.4\n'.codeUnits, ...'\n%%EOF'.codeUnits]);
    }
  });

  tearDownAll(() => docs.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('addFiles appends (bug 2: replace → append)', () {
    test('merge scenario: select one, add another → 2 files', () async {
      final c = container();
      final controller = c.read(jobFlowProvider.notifier);

      await controller.selectFiles([pdfPath]);
      expect(c.read(jobFlowProvider), isA<JobReady>());

      await controller.addFiles([pdfPath2]);
      final state = c.read(jobFlowProvider) as JobReady;
      expect(state.files.length, 2,
          reason: 'addFiles must APPEND, not replace');
      expect(state.files.map((f) => f.path), containsAll([pdfPath, pdfPath2]));
    });

    test('dedupes the same path picked twice', () async {
      final c = container();
      final controller = c.read(jobFlowProvider.notifier);
      await controller.selectFiles([pdfPath]);
      await controller.addFiles([pdfPath]);
      expect((c.read(jobFlowProvider) as JobReady).files.length, 1);
    });

    test('respects maxFiles: extra becomes a rejection', () async {
      final c = container();
      final controller = c.read(jobFlowProvider.notifier);
      await controller.selectFiles([pdfPath], maxFiles: 1);
      await controller.addFiles([pdfPath2], maxFiles: 1);
      final state = c.read(jobFlowProvider) as JobReady;
      expect(state.files.length, 1);
      expect(state.rejections, isNotEmpty);
    });

    test('invalid new picks keep the selection and explain why', () async {
      final c = container();
      final controller = c.read(jobFlowProvider.notifier);
      await controller.selectFiles([pdfPath]);

      final junk = '${docs.path}/junk.pdf';
      File(junk).writeAsBytesSync(List.generate(32, (i) => i));
      await controller.addFiles([junk]);

      final state = c.read(jobFlowProvider) as JobReady;
      expect(state.files.length, 1, reason: 'selection must survive');
      expect(state.rejections, isNotEmpty);
    });
  });

  group('tool entry resets stale state (bug 1: cross-tool leak)', () {
    testWidgets('JobReady from merge does not show inside split',
        (tester) async {
      final c = container();
      final controller = c.read(jobFlowProvider.notifier);
      await controller.selectFiles([pdfPath, pdfPath2]);
      expect(c.read(jobFlowProvider), isA<JobReady>());

      final splitTool =
          kPfTools.firstWhere((t) => t.id == 'pdf_split');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ToolFlowScreen(tool: splitTool),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.read(jobFlowProvider), isA<JobIdle>(),
          reason: 'entering a tool must reset the shared flow state');
      // The fresh Idle stage shows the pick CTA — not a stale selection.
      expect(find.text('Pick files'), findsOneWidget);
    });
  });
}
