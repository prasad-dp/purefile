import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/jobs/job_controller.dart' show appDocumentsPath;
import '../../core/privacy/usage_store.dart';
import '../../core/vault/vault_store.dart';

/// Where the vault is in its lifecycle. Drives the whole /vault screen.
enum VaultPhase {
  /// No vault exists yet: offer setup (create secret → initialize).
  uninitialized,

  /// Vault exists but is fully locked: secret (or biometrics) required.
  lockedHard,

  /// Key is in memory, but the screen needs a biometric confirm to show files.
  lockedSoft,

  /// Open for business.
  unlocked,
}

/// Session state for the vault screen.
final class VaultSessionState {
  const VaultSessionState({
    required this.phase,
    this.items = const [],
    this.busy = false,
    this.lastError,
  });

  final VaultPhase phase;
  final List<VaultItem> items;
  final bool busy;

  /// Human-facing message for a failed unlock/auth attempt (null = none).
  final String? lastError;

  VaultSessionState withPhase(VaultPhase p) => VaultSessionState(
        phase: p,
        items: items,
        busy: busy,
        lastError: lastError,
      );

  VaultSessionState withItems(List<VaultItem> i) => VaultSessionState(
        phase: phase,
        items: i,
        busy: busy,
        lastError: lastError,
      );

  VaultSessionState copyWith({bool? busy, String? lastError}) =>
      VaultSessionState(
        phase: phase,
        items: items,
        busy: busy ?? this.busy,
        lastError: lastError,
      );
}

/// Injectable auth hook — device build wires [localAuthGate], tests stub it.
typedef VaultBiometricGate = Future<bool> Function();

/// Real device gate. Returns false when biometrics fail, are cancelled, or
/// the device can't do them at all (caller falls back to the secret).
Future<bool> localAuthGate() async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return false;
    return await auth.authenticate(
      localizedReason: 'Unlock your Private Vault',
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    // Missing enrollment, plugin/platform error, user cancel — all just
    // "not authenticated"; the secret unlock remains the fallback.
    return false;
  }
}

/// Provider seam so widget tests can stub the biometric prompt.
final vaultBiometricGateProvider =
    Provider<VaultBiometricGate>((_) => localAuthGate);

/// Builds the storage for the device vault. Tests inject [InMemoryKeyStorage]
/// and a temp dir instead.
VaultKeyStorage defaultVaultKeyStorage() => SecureStorageKeyStorage();

/// Device storage: flutter_secure_storage (Android Keystore-backed
/// EncryptedSharedPreferences / iOS Keychain). Only ever holds the WRAPPED
/// vault key — never the plaintext key, never file bytes.
class SecureStorageKeyStorage implements VaultKeyStorage {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Session controller: owns the [VaultStore], exposes phase transitions and
/// the auto-lock policy (feature 14 contract: soft lock after 3 min
/// backgrounded, hard lock after 10 min).
class VaultSession extends Notifier<VaultSessionState> {
  static const softLockAfter = Duration(minutes: 3);
  static const hardLockAfter = Duration(minutes: 10);

  VaultStore? _store;
  DateTime? _backgroundedAt;
  bool _biometricsUsable = false;
  Duration _softLockAfter = softLockAfter;
  Duration _hardLockAfter = hardLockAfter;
  bool Function()? _biometricsProbeOverride;

  VaultStore get store {
    final s = _store;
    if (s == null) throw StateError('vault session not started');
    return s;
  }

  @override
  VaultSessionState build() => const VaultSessionState(phase: VaultPhase.uninitialized);

  /// (Re)creates the store for a device vault rooted at [rootDir]. Call once
  /// from the vault screen's init; safe to call again (re-creates the store).
  /// The optional overrides exist for tests (temp dir, stub gate, short
  /// auto-lock timings); the device build passes none of them.
  void attach({
    required String rootDir,
    VaultKeyStorage? keyStorage,
    VaultBiometricGate? gate,
    bool Function()? biometricsProbe,
    Duration? softLockAfter,
    Duration? hardLockAfter,
  }) {
    _store = VaultStore(
        rootDir: rootDir, keyStorage: keyStorage ?? defaultVaultKeyStorage());
    _gateOverride = gate;
    _biometricsProbeOverride = biometricsProbe;
    if (softLockAfter != null) _softLockAfter = softLockAfter;
    if (hardLockAfter != null) _hardLockAfter = hardLockAfter;
    _refreshPhase();
  }

  VaultBiometricGate? _gateOverride;

  VaultBiometricGate get _gate => _gateOverride ?? localAuthGate;

  /// Re-evaluates where the session stands (attach / lifecycle changes).
  Future<void> _refreshPhase() async {
    final s = store;
    final initialized = await s.isInitialized();
    if (!initialized) {
      state = state.withPhase(VaultPhase.uninitialized);
      return;
    }
    if (s.isUnlocked) {
      final items = await _safeItems();
      state = VaultSessionState(phase: VaultPhase.unlocked, items: items);
    } else {
      state = state.withPhase(VaultPhase.lockedHard);
    }
  }

  Future<List<VaultItem>> _safeItems() {
    try {
      return store.loadItems();
    } catch (_) {
      return Future.value(const <VaultItem>[]);
    }
  }

  /// Setup: create the vault with [secret] and confirm via [confirm].
  Future<bool> initialize(String secret, String confirm) async {
    if (secret.length < 8) {
      state = state.copyWith(lastError: 'Secret must be at least 8 characters');
      return false;
    }
    if (secret != confirm) {
      state = state.copyWith(lastError: 'Secrets do not match');
      return false;
    }
    try {
      await store.initialize(secret);
      _biometricsUsable = await _probeBiometrics();
      await _refreshPhase();
      return true;
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return false;
    }
  }

  /// Unlock with the recovery secret. Always available.
  Future<bool> unlockWithSecret(String secret) async {
    try {
      final ok = await store.unlock(secret);
      if (!ok) {
        state = state.copyWith(lastError: 'Wrong secret');
        return false;
      }
      _biometricsUsable = await _probeBiometrics();
      await _refreshPhase();
      return true;
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return false;
    }
  }

  /// Soft-lock → biometric confirm re-entry. Falls back gracefully: if the
  /// device cannot do biometrics (probe failed, no hardware), soft lock
  /// degrades to hard lock (secret prompt) instead of an unlock loop.
  Future<bool> unlockWithBiometrics() async {
    // NOTE: gate on the PHASE, not store.isUnlocked — a soft-locked vault
    // still holds its key in memory; the biometric check is exactly what
    // must not be skipped in that state.
    if (state.phase != VaultPhase.lockedSoft) {
      state = state.copyWith(
          lastError: 'Biometrics unavailable — use your secret');
      return false;
    }
    if (!_biometricsUsable) {
      state = state.copyWith(lastError: 'Biometrics unavailable — use your secret');
      return false;
    }
    final ok = await _gate();
    if (!ok) {
      state = state.copyWith(lastError: 'Authentication failed');
      return false;
    }
    // Key was kept in memory across the soft lock — nothing to re-derive.
    await _refreshPhase();
    if (state.phase != VaultPhase.unlocked) {
      // Biometrics passed but the key was dropped anyway (should not happen):
      // never fake an unlock.
      state = state.copyWith(lastError: 'Use your secret to unlock');
      return false;
    }
    return true;
  }

  /// Manual lock from the UI. [soft] keeps the key in memory so biometrics
  /// can re-gate the session; without usable biometrics it degrades to a hard
  /// lock (secret prompt).
  Future<void> lockNow({bool soft = false}) async {
    if (!store.isUnlocked) return;
    if (soft && _biometricsUsable) {
      state = state.withPhase(VaultPhase.lockedSoft);
      return;
    }
    await _wipeViews();
    store.hardLock();
    await _refreshPhase();
  }

  /// App backgrounded: start counting toward auto-lock.
  void onBackground() => _backgroundedAt = DateTime.now();

  /// App foregrounded: apply soft/hard lock per elapsed time.
  Future<void> onForeground() async {
    final bgAt = _backgroundedAt;
    _backgroundedAt = null;
    if (bgAt == null || !store.isUnlocked) return;
    final away = DateTime.now().difference(bgAt);
    if (away >= _hardLockAfter) {
      await _wipeViews();
      store.hardLock();
    } else if (away >= _softLockAfter) {
      // Soft lock: keep the key in memory, force biometric re-entry.
      state = state.withPhase(VaultPhase.lockedSoft);
      await unlockWithBiometrics();
      return;
    }
    await _refreshPhase();
  }

  Future<bool> _probeBiometrics() async {
    final probe = _biometricsProbeOverride;
    if (probe != null) return probe();
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Item operations (all require an unlocked store; UI shows busy state).
  // -------------------------------------------------------------------------

  Future<void> importFile(String sourcePath) async {
    state = state.copyWith(busy: true, lastError: null);
    try {
      // PERFORMANCE: the heavy parts (AES, 3-pass secure delete) run inside
      // the store on worker isolates — the UI stays responsive.
      final item = await store.importFile(sourcePath);
      // F15 privacy counters: one vaulted file, its plaintext size.
      try {
        await ref.read(usageStoreProvider).apply(
              UsageVaulted(count: 1, bytes: item.sizeBytes),
            );
      } catch (_) {
        // Counters are best-effort.
      }
      state = state.withItems(await _safeItems());
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> exportTo(String id, String outputDir) async {
    state = state.copyWith(busy: true, lastError: null);
    try {
      await store.exportTo(id, outputDir);
      state = state.withItems(await _safeItems());
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// In-place view: decrypts to a private per-session views dir and hands
  /// (path) to the caller for OpenFilex. The vault copy stays; the plaintext
  /// is wiped when the session ends (hard lock / destroy / new view round).
  Future<String?> viewItem(String id) async {
    state = state.copyWith(busy: true, lastError: null);
    try {
      final docs = await appDocumentsPath();
      final viewsDir = '$docs${Platform.pathSeparator}vault_views';
      return await store.viewTo(id, viewsDir);
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return null;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Type-aware save-back: runs the OS save dialog (SAF on Android — it
  /// starts in the type-matching collection: Pictures for images, Documents
  /// for PDFs …) and writes the decrypted bytes where the user picks. The
  /// vault copy always stays encrypted in place. Returns the chosen path or
  /// null on cancel.
  Future<String?> saveItemBack(String id, String fileName) async {
    state = state.copyWith(busy: true, lastError: null);
    try {
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      final bytes = await store.plainBytesOf(id);
      final picked = await FilePicker.platform.saveFile(
        fileName: fileName,
        type: switch (ext) {
          'jpg' || 'jpeg' || 'png' || 'webp' || 'heic' || 'gif' => FileType.image,
          'mp4' || 'mov' || 'avi' || 'mkv' => FileType.video,
          'mp3' || 'm4a' || 'wav' || 'aac' || 'flac' => FileType.audio,
          _ => FileType.any,
        },
        // SAF needs raw bytes when no initialDirectory applies.
        bytes: bytes,
      );
      return picked;
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return null;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Wipes decrypted view files (session end). Called on hard lock.
  Future<void> _wipeViews() async {
    try {
      final docs = await appDocumentsPath();
      store.wipeViews('$docs${Platform.pathSeparator}vault_views');
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(busy: true, lastError: null);
    try {
      await store.remove(id);
      state = state.withItems(await _safeItems());
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Full teardown — requires the correct secret, verified by the store.
  Future<bool> reset(String secret) async {
    try {
      final ok = await store.reset(secret);
      if (!ok) {
        state = state.copyWith(lastError: 'Wrong secret');
        return false;
      }
      _biometricsUsable = false;
      await _wipeViews();
      state = const VaultSessionState(phase: VaultPhase.uninitialized);
      return true;
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return false;
    }
  }

  /// Clears the snackbar-shown error (called after display).
  void clearError() {
    if (state.lastError == null) return;
    state = state.copyWith(lastError: null);
  }
}

/// App-wide vault session instance.
final vaultSessionProvider =
    NotifierProvider<VaultSession, VaultSessionState>(VaultSession.new);
