import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/monetization/monetization_providers.dart';
import 'core/privacy/crash_log_store.dart';
import 'core/share_intake/share_intake.dart';

/// Global crash safety net (docs/architecture.md — reliability rules):
/// everything lands in a capped local ring buffer (F15 CrashLogStore),
/// is surfaced in Settings → Privacy dashboard → Crash log, and the app
/// never white-screens. F15: one shared store for writers and readers.
void main() {
  final crashLog = CrashLogStore();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crashLog.append('flutter', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashLog.append('platform', error.toString());
    return true;
  };
  // ProviderScope is REQUIRED for every ref-based screen (was missing — a
  // latent crash on device, masked by tests that never pumped ref screens).
  // F16: the share-intake controller starts listening here, app-level.
  runApp(
    ProviderScope(
      child: _ShareIntakeBoot(child: const PureFileApp()),
    ),
  );
}

class _ShareIntakeBoot extends ConsumerStatefulWidget {
  const _ShareIntakeBoot({required this.child});

  final Widget child;

  @override
  ConsumerState<_ShareIntakeBoot> createState() => _ShareIntakeBootState();
}

class _ShareIntakeBootState extends ConsumerState<_ShareIntakeBoot> {
  @override
  void initState() {
    super.initState();
    // Registers the cold-start pull + warm-share stream once for the app.
    ref.read(shareIntakeProvider.notifier).start();
    // Initialize monetization and ads safely.
    ref.read(billingServiceProvider).initialize();
    ref.read(adsServiceProvider).initialize();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
