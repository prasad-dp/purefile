import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/privacy/usage_store.dart';
import '../../core/theme.dart';
import '../../core/tools.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/ios_group.dart';

/// Privacy dashboard (F19b): the numbers that prove the offline promise,
/// rendered as iOS inset groups — stat pair on gradient plates, grouped
/// facts/tools/crash-log rows.
class PrivacyDashboardScreen extends ConsumerWidget {
  const PrivacyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final stats =
        ref.watch(usageStatsProvider).valueOrNull ?? const UsageStats();
    final topTools = stats.toolsByCount().take(3).toList();

    return Scaffold(
      appBar: AppBar(title: Text(loc.privacyDashboard)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          // The headline pair, as two gradient plates.
          Padding(
            padding: const EdgeInsets.fromLTRB(pfGroupH, 8, pfGroupH, 8),
            child: Row(
              children: [
                Expanded(
                  child: _StatPlate(
                    gradient: PfColors.heroGradient,
                    icon: Icons.done_all_rounded,
                    value: '${stats.totalCount}',
                    label: loc.privacyProcessed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatPlate(
                    gradient: LinearGradient(colors: [
                      PfColors.info,
                      PfColors.info.withValues(alpha: 0.75),
                    ]),
                    icon: Icons.cloud_off_rounded,
                    value: '0',
                    label: loc.privacyUploaded,
                  ),
                ),
              ],
            ),
          ),

          PfSectionHeader(loc.privacyFactsTitle),
          PfSection(
            child: Column(
              children: [
                PfGroupItem(
                  title: loc.privacyFactOffline,
                  leading: const _IconPlate(
                      icon: Icons.wifi_off_rounded, color: PfColors.info),
                  first: true,
                ),
                PfGroupItem(
                  title: loc.privacyFactNoAccount,
                  leading: const _IconPlate(
                      icon: Icons.person_off_rounded, color: PfColors.warning),
                ),
                PfGroupItem(
                  title: loc.privacyFactNoTracking,
                  leading: const _IconPlate(
                      icon: Icons.not_interested_rounded,
                      color: PfColors.error),
                  last: true,
                ),
              ],
            ),
          ),

          if (topTools.isNotEmpty) ...[
            PfSectionHeader(loc.privacyTopTools),
            PfSection(
              child: Column(
                children: [
                  for (var i = 0; i < topTools.length; i++)
                    PfGroupItem(
                      title: _toolTitle(topTools[i].key),
                      trailing: Text(
                        '${topTools[i].value}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      first: i == 0,
                      last: i == topTools.length - 1,
                    ),
                ],
              ),
            ),
          ],


          PfSectionHeader(loc.crashLogTitle),
          PfSection(
            child: PfGroupItem(
              title: loc.crashLogTitle,
              subtitle: loc.crashLogSubtitle,
              leading: const _IconPlate(
                  icon: Icons.bug_report_rounded, color: PfColors.categoryPdf),
              showChevron: true,
              first: true,
              onTap: () => context.push('/privacy/crash-log'),
            ),
          ),

          // Reset — quiet destructive row at the bottom.
          PfSection(
            child: PfGroupItem(
              title: loc.privacyResetAction,
              destructive: true,
              showChevron: false,
              first: true,
              last: true,
              onTap: stats.totalCount == 0
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(loc.privacyResetTitle),
                          content: Text(loc.privacyResetBody),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              child: Text(loc.cancel),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(true),
                              child: Text(loc.privacyResetConfirm),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref.read(usageStatsProvider.notifier).resetAll();
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  String _toolTitle(String toolId) {
    for (final t in kPfTools) {
      if (t.id == toolId) return t.title;
    }
    return toolId;
  }
}

/// Gradient stat plate (the hero pair).
class _StatPlate extends StatelessWidget {
  const _StatPlate({
    required this.gradient,
    required this.icon,
    required this.value,
    required this.label,
  });

  final Gradient gradient;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
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
