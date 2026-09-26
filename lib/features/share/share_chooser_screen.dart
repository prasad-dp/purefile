import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/share_intake/share_intake.dart';
import '../../core/tools.dart';
import '../../l10n/generated/app_localizations.dart';
import '../tools/tool_flow_screen.dart' show toolUiSpec;

/// Share-intake chooser (feature 16): files shared into PureFile land here
/// with the eligible tools listed. One tap = tool opens with the files
/// already selected and validated. Empty-state: no tool can process the
/// selection (never a silent dead end).
class ShareChooserScreen extends ConsumerStatefulWidget {
  const ShareChooserScreen({super.key});

  @override
  ConsumerState<ShareChooserScreen> createState() => _ShareChooserScreenState();
}

class _ShareChooserScreenState extends ConsumerState<ShareChooserScreen> {
  List<String>? _paths;
  List<String>? _eligible;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  Future<void> _evaluate() async {
    final pending = ref.read(shareIntakeProvider);
    var eligible = <String>[];
    if (pending.isNotEmpty) {
      // Same validation the tool flow itself applies — the chooser never
      // offers a tool that would reject these files.
      eligible = await eligibleToolIds(
        pending,
        specFor: (toolId) {
          final spec = toolUiSpec(toolId);
          return (allowedMagic: spec.allowedMagic, maxFiles: spec.maxFiles);
        },
      );
    }
    if (mounted) {
      setState(() {
        _paths = pending;
        _eligible = eligible;
      });
    }
  }

  void _openTool(String toolId) {
    final paths = ref.read(shareIntakeProvider.notifier).consume();
    if (paths.isEmpty || !mounted) return;
    final tool = kPfTools.firstWhere(
      (t) => t.id == toolId,
      orElse: () => kPfTools.first,
    );
    context.push(tool.route);
  }

  void _dismiss() {
    ref.read(shareIntakeProvider.notifier).discard();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final paths = _paths;
    final eligible = _eligible;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.shareChooserTitle),
        actions: [
          IconButton(
            tooltip: loc.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: _dismiss,
          ),
        ],
      ),
      body: paths == null || eligible == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    loc.shareChooserCount(paths.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: eligible.isEmpty
                      ? _NoToolFits(paths: paths)
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: eligible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final toolId = eligible[i];
                            final tool = kPfTools
                                .firstWhere((t) => t.id == toolId);
                            return Card(
                              child: ListTile(
                                leading: Icon(tool.icon, color: scheme.primary),
                                title: Text(tool.title),
                                subtitle: Text(tool.subtitle),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () => _openTool(toolId),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _NoToolFits extends StatelessWidget {
  const _NoToolFits({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rule_rounded,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              loc.shareChooserNoTool,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              loc.shareChooserNoToolBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
