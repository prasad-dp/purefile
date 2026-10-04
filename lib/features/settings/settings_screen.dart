import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/appearance.dart';
import '../../core/errors.dart' show formatMb;
import '../../core/monetization/monetization_providers.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/ios_group.dart';

/// Settings: iOS inset-grouped rows — appearance with the theme-mode
/// segmented control, storage & cache cleaner, privacy dashboard, and about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _tempCacheBytes;
  int? _outputsBytes;
  int? _outputsCount;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    int tempBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(recursive: true)) {
          if (entity is File) {
            tempBytes += entity.lengthSync();
          }
        }
      }
      final docs = await getApplicationDocumentsDirectory();
      final scanSession =
          Directory('${docs.path}${Platform.pathSeparator}scan_session');
      if (scanSession.existsSync()) {
        for (final entity in scanSession.listSync(recursive: true)) {
          if (entity is File) {
            tempBytes += entity.lengthSync();
          }
        }
      }
    } catch (_) {}

    int outBytes = 0;
    int outCount = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outDir = Directory('${docs.path}${Platform.pathSeparator}outputs');
      if (outDir.existsSync()) {
        for (final entity in outDir.listSync(recursive: true)) {
          if (entity is File) {
            outBytes += entity.lengthSync();
            outCount++;
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _tempCacheBytes = tempBytes;
        _outputsBytes = outBytes;
        _outputsCount = outCount;
      });
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      final docs = await getApplicationDocumentsDirectory();
      final scanSession =
          Directory('${docs.path}${Platform.pathSeparator}scan_session');
      if (scanSession.existsSync()) {
        scanSession.deleteSync(recursive: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Temporary cache cleared'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _clearingCache = false);
        unawaited(_refreshStorage());
      }
    }
  }

  Future<void> _clearOutputs() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.clearOutputsTitle),
        content: Text(loc.clearOutputsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(loc.clearOutputsConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}outputs');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved output files removed'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) unawaited(_refreshStorage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          const PfSectionHeader('Membership'),
          PfSection(
            child: PfGroupItem(
              title: isPro ? 'PureFile Pro Active' : 'Upgrade to PureFile Pro',
              subtitle: isPro
                  ? 'All features unlocked · 100% ad-free'
                  : '500 MB file cap, 100-file batches, zero ads',
              leading: const _IconPlate(
                icon: Icons.workspace_premium_rounded,
                color: Color(0xFFF59E0B),
              ),
              trailing: isPro
                  ? const Icon(Icons.verified_rounded, color: Color(0xFF10B981))
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/pro'),
              first: true,
              last: true,
            ),
          ),
          PfSectionHeader(loc.appearanceSection),
          PfSection(
            child: Column(
              children: [
                PfGroupItem(
                  title: loc.appearanceMode,
                  subtitle: loc.appearanceModeBody,
                  leading: const _IconPlate(
                    icon: Icons.contrast_rounded,
                    color: PfColors.primaryLight,
                  ),
                  first: true,
                  last: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
          const PfSectionHeader('Storage & Cache'),
          PfSection(
            child: Column(
              children: [
                PfGroupItem(
                  title: 'Temporary Cache',
                  subtitle: _tempCacheBytes == null
                      ? loc.storageCalculating
                      : '${formatMb(_tempCacheBytes!)} · Cached buffers & temporary scans',
                  leading: const _IconPlate(
                    icon: Icons.cleaning_services_rounded,
                    color: PfColors.warning,
                  ),
                  trailing: _clearingCache
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed:
                              (_tempCacheBytes ?? 0) == 0 ? null : _clearCache,
                          child: const Text('Clean'),
                        ),
                  first: true,
                ),
                PfGroupItem(
                  title: loc.storageOutputsTitle,
                  subtitle: _outputsBytes == null
                      ? loc.storageCalculating
                      : loc.storageOutputsBody(
                          _outputsCount ?? 0,
                          formatMb(_outputsBytes ?? 0),
                        ),
                  leading: const _IconPlate(
                    icon: Icons.folder_open_rounded,
                    color: PfColors.categoryZip,
                  ),
                  trailing: TextButton(
                    onPressed:
                        (_outputsCount ?? 0) == 0 ? null : _clearOutputs,
                    child: Text(loc.clearOutputsAction),
                  ),
                  last: true,
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
                  leading: const _IconPlate(
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
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/brand/icon_1024.png',
                  width: 32,
                  height: 32,
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
