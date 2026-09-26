import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/privacy/crash_log_store.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Crash-log viewer (F19b): grouped cards, tinted severity plates, crafted
/// empty state with the reassurance front and center.
class CrashLogScreen extends ConsumerStatefulWidget {
  const CrashLogScreen({super.key});

  @override
  ConsumerState<CrashLogScreen> createState() => _CrashLogScreenState();
}

class _CrashLogScreenState extends ConsumerState<CrashLogScreen> {
  List<CrashEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(crashLogStoreProvider).load();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.crashLogClearTitle),
        content: Text(loc.crashLogClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(loc.crashLogClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(crashLogStoreProvider).clear();
    if (mounted) {
      setState(() => _entries = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.crashLogTitle),
        actions: [
          if (entries != null && entries.isNotEmpty) ...[
            IconButton(
              tooltip: loc.share,
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () {
                final text = [
                  for (final e in entries)
                    '${e.at.toIso8601String()} [${e.source}] ${e.message}',
                ].join('\n');
                SharePlus.instance.share(ShareParams(text: text));
              },
            ),
            IconButton(
              tooltip: loc.crashLogClearConfirm,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _clear,
            ),
          ],
        ],
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: PfColors.success.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user_rounded,
                              size: 32, color: PfColors.success),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          loc.crashLogEmpty,
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
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final isFlutter = e.source == 'flutter';
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: (isFlutter ? PfColors.warning : PfColors.error)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            isFlutter
                                ? Icons.warning_amber_rounded
                                : Icons.dangerous_rounded,
                            size: 18,
                            color: isFlutter ? PfColors.warning : PfColors.error,
                          ),
                        ),
                        title: Text(e.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, letterSpacing: -0.1)),
                        subtitle: Text(
                          '${e.source} · '
                          '${e.at.toLocal().toString().substring(0, 19)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
