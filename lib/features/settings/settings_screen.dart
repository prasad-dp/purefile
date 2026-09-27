import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/ios_group.dart';

/// Settings (F19b): iOS inset-grouped rows — appearance with the theme-mode
/// segmented control, dashboard with chevron, about with the real brand mark.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          PfSectionHeader(loc.appearanceSection),
          PfSection(
            child: Column(
              children: [
                PfGroupItem(
                  title: loc.appearanceMode,
                  subtitle: loc.appearanceModeBody,
                  leading: _IconPlate(
                    icon: Icons.contrast_rounded,
                    color: PfColors.primaryLight,
                  ),
                  first: true,
                  last: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  // Segmented control styled by the theme in both modes —
                  // tinted container + themed thumb/text. Material's native
                  // segmented control (iOS grammar, no custom painting).
                  child: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(_modeIcon(ThemeMode.system), size: 18),
                        label: Text(_modeLabel(loc, ThemeMode.system)),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(_modeIcon(ThemeMode.light), size: 18),
                        label: Text(_modeLabel(loc, ThemeMode.light)),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(_modeIcon(ThemeMode.dark), size: 18),
                        label: Text(_modeLabel(loc, ThemeMode.dark)),
                      ),
                    ],
                    selected: {mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      PfHaptics.tap();
                      ref
                          .read(themeModeProvider.notifier)
                          .setMode(selection.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          PfSection(
            child: Column(
              children: [
                PfGroupItem(
                  title: loc.privacyDashboard,
                  subtitle: loc.privacyDashboardBody,
                  leading: _IconPlate(
                    icon: Icons.verified_user_rounded,
                    color: PfColors.success,
                  ),
                  showChevron: true,
                  first: true,
                  last: true,
                  onTap: () => context.push('/privacy'),
                ),
              ],
            ),
          ),
          PfSection(
            child: PfGroupItem(
              title: loc.aboutTitle,
              subtitle: loc.aboutBody,
              leading: Image.asset(
                // Launcher-look composite (circle-masked) so the in-app logo
                // matches the icon on the home screen exactly.
                'assets/brand/icon_launcher.png',
                width: 36,
                height: 36,
                fit: BoxFit.contain,
              ),
              first: true,
              last: true,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _modeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

String _modeLabel(AppLocalizations loc, ThemeMode mode) => switch (mode) {
      ThemeMode.system => loc.appearanceAuto,
      ThemeMode.light => loc.appearanceLight,
      ThemeMode.dark => loc.appearanceDark,
    };

/// iOS-style tinted rounded icon plate for group rows.
class _IconPlate extends StatelessWidget {
  const _IconPlate({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}
