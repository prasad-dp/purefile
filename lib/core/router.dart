import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_screen.dart';
import '../features/history/history_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/share/share_chooser_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/crash_log_screen.dart';
import '../features/settings/privacy_dashboard_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sign/sign_screen.dart';
import '../features/tools/tool_flow_screen.dart';
import '../features/vault/vault_screen.dart';

final GoRouter pfRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('pf_onboarding_done') ?? false;
    if (!done && state.uri.path == '/') return '/onboarding';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
    GoRoute(
        path: '/privacy', builder: (context, state) => const PrivacyDashboardScreen()),
    GoRoute(
        path: '/privacy/crash-log',
        builder: (context, state) => const CrashLogScreen()),
    GoRoute(
        path: '/share', builder: (context, state) => const ShareChooserScreen()),
    // NOTE: static tool routes MUST precede the /tools/:toolId catch-all —
    // go_router matches in declaration order and the parameterized route
    // would otherwise shadow them (caught while wiring F13).
    GoRoute(path: '/tools/scan', builder: (context, state) => const ScanScreen()),
    GoRoute(path: '/tools/sign', builder: (context, state) => const SignScreen()),
    GoRoute(path: '/tools/vault', builder: (context, state) => const VaultScreen()),
    GoRoute(path: '/tools/:toolId', builder: toolFlowBuilder),
  ],
);
