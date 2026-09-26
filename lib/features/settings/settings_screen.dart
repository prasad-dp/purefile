import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/ios_group.dart';

/// Settings (F19b): iOS inset-grouped rows — dashboard with chevron, about
/// with the real brand mark. Crafted, not assembled.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(loc.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
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
                  onTap: () => context.push('/privacy'),
                ),
              ],
            ),
          ),
          PfSection(
            child: PfGroupItem(
              title: loc.aboutTitle,
              subtitle: loc.aboutBody,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/brand/icon_1024.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
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
