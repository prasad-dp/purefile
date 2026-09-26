import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/history/history_store.dart';
import '../../core/theme.dart';
import '../../core/tools.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/ios_group.dart';

/// Local outputs history (F19b): iOS grouped rows — tinted type-icon plates,
/// hairline separators, swipe-to-delete kept, crafted empty state.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<HistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await ref.read(historyProvider).load();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _confirmClear() async {
    final loc = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.historyClearTitle),
        content: Text(loc.historyClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.historyClearConfirm),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(historyProvider).clear();
      if (mounted) setState(() => _entries = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.historyTitle),
        actions: [
          IconButton(
            tooltip: loc.historyClearTitle,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: switch (entries) {
        null => const Center(child: CircularProgressIndicator()),
        [] => _EmptyState(loc: loc),
        _ => ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              // Group into floating cards of soft shadow; keep swipe.
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: pfGroupH, vertical: 4),
                child: Dismissible(
                  key: ValueKey(
                      '${e.path}-${e.createdAt.millisecondsSinceEpoch}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(
                      color: PfColors.error.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    setState(() => entries.removeAt(i));
                    await ref.read(historyProvider).remove(e.path);
                  },
                  child: Card(
                    child: ListTile(
                      leading: _TypePlate(icon: _iconFor(e)),
                      title: Text(e.fileName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_toolLabel(e.toolId)} · ${_fmtBytes(e.sizeBytes)} · ${_fmtDate(e.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: loc.share,
                        icon: Icon(Icons.ios_share_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary),
                        onPressed: () => e.isDirectory
                            ? _shareFolder(e)
                            : SharePlus.instance.share(
                                ShareParams(files: [XFile(e.path)]),
                              ),
                      ),
                      onTap: () => OpenFilex.open(e.path),
                    ),
                  ),
                ),
              );
            },
          ),
      },
    );
  }

  Future<void> _shareFolder(HistoryEntry e) async {
    final dir = Directory(e.path);
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().take(20).toList();
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: [for (final f in files) XFile(f.path)]),
    );
  }

  IconData _iconFor(HistoryEntry e) {
    if (e.isDirectory) return Icons.folder_zip_outlined;
    final n = e.fileName.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (n.endsWith('.zip')) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (diff == 0) return '$hh:$mm';
    if (diff == 1) return 'Yesterday $hh:$mm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}

/// Tinted type plate — softer than the settings plates (history rows repeat).
class _TypePlate extends StatelessWidget {
  const _TypePlate({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 19, color: scheme.primary),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loc});

  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_rounded,
                  size: 32, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              loc.historyEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titles come from the tool registry so they never drift from the grid.
String _toolLabel(String toolId) {
  for (final t in kPfTools) {
    if (t.id == toolId) return t.title;
  }
  return toolId;
}
