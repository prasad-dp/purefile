import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/appearance.dart';
import 'core/router.dart';
import 'core/share_intake/share_intake.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';

class PureFileApp extends ConsumerStatefulWidget {
  const PureFileApp({super.key});

  @override
  ConsumerState<PureFileApp> createState() => _PureFileAppState();
}

class _PureFileAppState extends ConsumerState<PureFileApp> {
  /// Flow tools auto-fill from a pending share themselves; the custom-screen
  /// routes do not (F16).
  static const _customToolPaths = {'/tools/scan', '/tools/sign', '/tools/vault'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Restore the persisted theme mode BEFORE anything else: the first
      // frame must already carry the right brightness (no light flash for
      // dark-mode users). Share routing follows the same gate.
      await ref.read(appearanceReadyProvider.future);
      // F16: app-level share intake — cold start (launched by a share) and
      // the warm-share stream both land in the intake controller.
      await ref.read(shareIntakeProvider.notifier).start();
      _routePendingShare();
    });
  }

  void _routePendingShare() {
    final pending = ref.read(shareIntakeProvider);
    if (pending.isEmpty || !mounted) return;
    final path = pfRouter.routerDelegate.currentConfiguration.uri.path;
    // Inside a generic flow tool: that screen's own listener auto-fills —
    // no chooser. Already on the chooser: it re-evaluates itself.
    final inGenericFlow =
        path.startsWith('/tools/') && !_customToolPaths.contains(path);
    if (inGenericFlow || path == '/share') return;
    pfRouter.push('/share');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(shareIntakeProvider, (prev, next) {
      if (next.isNotEmpty) _routePendingShare();
    });

    return MaterialApp.router(
      title: 'PureFile',
      debugShowCheckedModeBanner: false,
      theme: PfTheme.light(),
      darkTheme: PfTheme.dark(),
      // Light/dark feature: the user's persisted choice (defaults to system).
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: pfRouter,
    );
  }
}
