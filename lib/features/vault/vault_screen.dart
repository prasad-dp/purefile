import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/jobs/job_controller.dart';
import '../../core/theme.dart' show PfColors;
import '../../core/vault/vault_store.dart';
import '../../l10n/generated/app_localizations.dart';
import 'vault_session.dart';

/// Private Vault (feature 14): setup → lock screens → encrypted file list.
/// The session controller owns all state; this widget is views + intents.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attach after the first frame: attach() does sync disk probes and the
    // session must exist before any phase call. Gate stays default (device).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final docs = await appDocumentsPath();
      ref.read(vaultSessionProvider.notifier).attach(
            rootDir:
                '$docs${Platform.pathSeparator}vault',
          );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(vaultSessionProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      session.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      session.onForeground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSessionProvider);
    _showErrorIfAny(state);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: _appBar(context, ref, state),
        body: switch (state.phase) {
          VaultPhase.uninitialized => const _SetupView(),
          VaultPhase.lockedHard => const _HardLockedView(),
          VaultPhase.lockedSoft => const _SoftLockedView(),
          VaultPhase.unlocked => _UnlockedView(items: state.items),
        },
      ),
    );
  }

  PreferredSizeWidget _appBar(
    BuildContext context,
    WidgetRef ref,
    VaultSessionState state,
  ) {
    final loc = AppLocalizations.of(context)!;
    final session = ref.read(vaultSessionProvider.notifier);
    return AppBar(
      title: Text(loc.vaultTitle),
      actions: [
        if (state.phase == VaultPhase.unlocked) ...[
          IconButton(
            tooltip: loc.vaultLockNow,
            icon: const Icon(Icons.lock_rounded),
            onPressed: () =>
                session.lockNow(soft: state.items.isNotEmpty),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'destroy') _confirmDestroy(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'destroy',
                child: Text(loc.vaultDestroy),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showErrorIfAny(VaultSessionState state) {
    final error = state.lastError;
    if (error == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      ref.read(vaultSessionProvider.notifier).clearError();
    });
  }

  Future<void> _confirmDestroy(BuildContext context, WidgetRef ref) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final secret = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.vaultDestroy),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: loc.vaultSecretLabel,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(loc.vaultDestroy),
          ),
        ],
      ),
    );
    if (secret == null || secret.isEmpty || !mounted) return;
    await ref.read(vaultSessionProvider.notifier).reset(secret);
  }
}

/// Open vault: encrypted file list + import / export / remove.
class _UnlockedView extends ConsumerStatefulWidget {
  const _UnlockedView({required this.items});

  final List<VaultItem> items;

  @override
  ConsumerState<_UnlockedView> createState() => _UnlockedViewState();
}

class _UnlockedViewState extends ConsumerState<_UnlockedView> {
  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    await ref.read(vaultSessionProvider.notifier).importFile(path);
  }

  /// In-place view: decrypts to a private views dir and opens with the OS
  /// viewer. The vault copy stays; the plaintext is wiped on session end.
  Future<void> _view(VaultItem item) async {
    final path = await ref.read(vaultSessionProvider.notifier).viewItem(item.id);
    if (path == null || !mounted) return;
    await OpenFilex.open(path);
  }

  /// Type-aware save-back: the OS save dialog starts in the type-matching
  /// collection (Pictures for images, Documents for PDFs …) and the file is
  /// written wherever the user picks. The vault copy stays encrypted.
  Future<void> _saveBack(VaultItem item) async {
    final path = await ref
        .read(vaultSessionProvider.notifier)
        .saveItemBack(item.id, item.name);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.vaultExportDone(item.name))),
      );
    }
  }

  Future<void> _remove(VaultItem item) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.vaultRemoveTitle),
        content: Text(loc.vaultRemoveBody(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(loc.vaultRemoveConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(vaultSessionProvider.notifier).remove(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final busy = ref.watch(vaultSessionProvider).busy;
    if (widget.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_special_rounded,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.vaultEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : _import,
              icon: const Icon(Icons.add_rounded),
              label: Text(loc.vaultImport),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : _import,
              icon: const Icon(Icons.add_rounded),
              label: Text(loc.vaultImport),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              return Card(
                child: ListTile(
                  leading: Icon(_iconFor(item),
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_subtitle(loc, item)),
                  // Tap = view in place (decrypt → OS viewer).
                  onTap: busy ? null : () => _view(item),
                  trailing: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : PopupMenuButton<String>(
                          onSelected: (v) => switch (v) {
                                'save' => _saveBack(item),
                                'remove' => _remove(item),
                                _ => null,
                              },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'save',
                              child: Text(loc.vaultSaveBack),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(loc.vaultRemoveConfirm),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _subtitle(AppLocalizations loc, VaultItem item) {
    final kb = item.sizeBytes / 1024;
    final size = kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.round()} KB';
    return '$size · ${loc.vaultEncryptedNote}';
  }

  /// Type-flavored icon so the list reads like a file browser.
  IconData _iconFor(VaultItem item) {
    final n = item.name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') ||
        n.endsWith('.webp') || n.endsWith('.heic')) {
      return Icons.image_outlined;
    }
    if (n.endsWith('.zip')) return Icons.folder_zip_outlined;
    if (n.endsWith('.mp4') || n.endsWith('.mov')) return Icons.movie_outlined;
    if (n.endsWith('.mp3') || n.endsWith('.m4a') || n.endsWith('.wav')) {
      return Icons.audiotrack_outlined;
    }
    return Icons.enhanced_encryption_rounded;
  }
}

/// First run: choose a secret, initialize the vault.
class _SetupView extends ConsumerStatefulWidget {
  const _SetupView();

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final busy = ref.watch(vaultSessionProvider).busy;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: PfColors.heroGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: PfColors.primaryLight.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc.vaultSetupTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              loc.vaultSetupBody,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _secret,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: loc.vaultSecretLabel,
                helperText: loc.vaultSecretHint,
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: loc.vaultSecretConfirm),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await ref
                          .read(vaultSessionProvider.notifier)
                          .initialize(_secret.text, _confirm.text);
                      if (ok && mounted) {
                        _secret.clear();
                        _confirm.clear();
                      }
                    },
              child: Text(loc.vaultCreate),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fully locked: secret entry (biometrics are only for the soft path).
class _HardLockedView extends ConsumerStatefulWidget {
  const _HardLockedView();

  @override
  ConsumerState<_HardLockedView> createState() => _HardLockedViewState();
}

class _HardLockedViewState extends ConsumerState<_HardLockedView> {
  final _secret = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final busy = ref.watch(vaultSessionProvider).busy;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: PfColors.heroGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: PfColors.primaryLight.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(loc.vaultLockedTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextField(
              controller: _secret,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onSubmitted: (_) => _unlock(),
              decoration: InputDecoration(labelText: loc.vaultSecretLabel),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _unlock,
              child: Text(loc.vaultUnlock),
            ),
          ],
        ),
      ),
    );
  }

  void _unlock() {
    ref.read(vaultSessionProvider.notifier).unlockWithSecret(_secret.text);
  }
}

/// Soft-locked: the key is in memory; biometrics (or the secret) re-gate.
class _SoftLockedView extends ConsumerWidget {
  const _SoftLockedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final busy = ref.watch(vaultSessionProvider).busy;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fingerprint_rounded,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(loc.vaultSoftLockTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => ref
                    .read(vaultSessionProvider.notifier)
                    .unlockWithBiometrics(),
            icon: const Icon(Icons.fingerprint_rounded),
            label: Text(loc.vaultUnlockBiometrics),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy
                ? null
                : () => _useSecretInstead(context, ref),
            child: Text(loc.vaultUseSecret),
          ),
        ],
      ),
    );
  }

  Future<void> _useSecretInstead(BuildContext context, WidgetRef ref) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final secret = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.vaultSecretLabel),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(loc.vaultUnlock),
          ),
        ],
      ),
    );
    if (secret == null || secret.isEmpty) return;
    await ref.read(vaultSessionProvider.notifier).unlockWithSecret(secret);
  }
}
