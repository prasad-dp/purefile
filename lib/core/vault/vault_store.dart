import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../errors.dart';
import '../file_io.dart';
import 'vault_crypto.dart';

/// Read/write access to the small key-value blob that holds the wrapped vault
/// key. Device impl: flutter_secure_storage (Android Keystore / iOS Keychain
/// backed). Test impl: [InMemoryKeyStorage].
abstract class VaultKeyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Non-persisting storage for tests.
class InMemoryKeyStorage implements VaultKeyStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// One encrypted file inside the vault. `id` is the on-disk blob name; the
/// readable [name] lives only inside the encrypted manifest.
final class VaultItem {
  const VaultItem({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.addedAt,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'size': sizeBytes,
        'at': addedAt.millisecondsSinceEpoch,
      };

  static VaultItem fromJson(Map<String, Object?> json) => VaultItem(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? 'file',
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0),
      );
}

/// The Private Vault (feature 14). Layout under [rootDir]:
///
/// ```
/// manifest.pfv  — AES-256-GCM encrypted JSON list of VaultItem
/// <id>.pfv      — AES-256-GCM encrypted file bytes (cipher||mac||nonce)
/// ```
///
/// Nothing on disk is plaintext: not the file bytes, not the file names (they
/// live inside the encrypted manifest), not the key. The wrapped key lives in
/// [VaultKeyStorage]; it is wrapped by a PBKDF2 key derived from the user
/// secret — see [VaultCrypto] for the full trust model.
///
/// Lock levels:
///  • hard lock — key dropped from memory; only the secret can re-derive it.
///  • soft lock — key kept in memory; biometrics (or the secret) gate re-entry.
class VaultStore {
  VaultStore({required this.rootDir, VaultKeyStorage? keyStorage})
      : _keyStorage = keyStorage ?? InMemoryKeyStorage();

  static const _wrappedKeyStorageKey = 'pf.vault.wrapped.v1';
  static const manifestName = 'manifest.pfv';
  static const blobSuffix = '.pfv';

  /// Vault imports are memory-buffered (encrypt in RAM), so cap below the
  /// general per-file pick limit.
  static const int maxImportBytes = 100 * 1024 * 1024;

  final String rootDir;
  final VaultKeyStorage _keyStorage;

  Uint8List? _key;

  bool get isUnlocked => _key != null;

  Directory get _dir => Directory(rootDir);

  File get _manifestFile =>
      File('$rootDir${Platform.pathSeparator}$manifestName');

  File _blobFile(String id) =>
      File('$rootDir${Platform.pathSeparator}$id$blobSuffix');

  /// True once a vault exists on disk (wrapped key + manifest both written —
  /// setup writes the key first, so a crash mid-setup never fakes this).
  Future<bool> isInitialized() async =>
      _manifestFile.existsSync() &&
      await _keyStorage.read(_wrappedKeyStorageKey) != null;

  /// Creates a fresh vault. Throws [StateError] if one already exists and
  /// [ArgumentError] for a too-short secret.
  Future<void> initialize(String secret) async {
    if (await isInitialized()) throw StateError('vault already initialized');
    if (secret.length < 8) throw ArgumentError('secret too short');
    _dir.createSync(recursive: true);
    final vaultKey = VaultCrypto.newVaultKey();
    // PERFORMANCE: PBKDF2 (150k iterations) is CPU-heavy — derive+wrap on a
    // worker isolate so the UI never freezes during setup.
    final wrapped = await Isolate.run(() => VaultCrypto.wrapKey(secret, vaultKey));
    await _keyStorage.write(_wrappedKeyStorageKey, base64Encode(wrapped));
    _key = vaultKey;
    await _writeManifest(const []);
  }

  /// Unwraps the vault key with [secret]. Returns true on success; false when
  /// the secret is wrong. [StateError] propagates for a vault that was never
  /// initialized or whose wrapped key is corrupt.
  Future<bool> unlock(String secret) async {
    if (_key != null) return true;
    final wrappedB64 = await _keyStorage.read(_wrappedKeyStorageKey);
    if (wrappedB64 == null) throw StateError('vault not initialized');
    final blob = base64Decode(wrappedB64);
    try {
      // PERFORMANCE: the PBKDF2 derivation inside unwrapKey runs on a worker
      // isolate — unlock must never freeze the UI for ~a second.
      _key = await Isolate.run(
          () => VaultCrypto.unwrapKey(secret, Uint8List.fromList(blob)));
    } on ArgumentError {
      return false;
    }
    return true;
  }

  /// Drops the key from memory. [hard] = false keeps it for soft-lock
  /// (biometrics can re-gate the session without re-deriving the key).
  void lock({bool hard = true}) {
    if (hard) _key = null;
  }

  /// Drops the key even on a soft lock (e.g. biometrics auth failed).
  void hardLock() => _key = null;

  Uint8List _requireKey() {
    final key = _key;
    if (key == null) throw StateError('vault is locked');
    return key;
  }

  /// Decrypted manifest — only available while unlocked.
  Future<List<VaultItem>> loadItems() async {
    final key = _requireKey();
    if (!_manifestFile.existsSync()) return const [];
    final blob = _manifestFile.readAsBytesSync();
    if (blob.isEmpty) return const [];
    final plain = await VaultCrypto.decrypt(key, blob);
    final list = jsonDecode(utf8.decode(plain)) as List<dynamic>;
    return [
      for (final e in list) VaultItem.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  /// Encrypts [sourcePath] into the vault and, once the encrypted copy +
  /// manifest are durably written, secure-deletes the plaintext original.
  Future<VaultItem> importFile(String sourcePath) async {
    final key = _requireKey();
    final src = File(sourcePath);
    if (!src.existsSync()) throw StateError('source file missing');
    final name = src.uri.pathSegments.last;
    final size = src.lengthSync();
    if (size > maxImportBytes) {
      throw FileTooLarge(
        fileName: name,
        sizeBytes: size,
        limitBytes: maxImportBytes,
      );
    }
    final plain = await src.readAsBytes();
    final id = _newId();
    final blobPath = _blobFile(id).path;
    // PERFORMANCE: AES over the whole file + the 3-pass secure delete of the
    // original are CPU/IO-heavy — both run on a worker isolate. The closure
    // captures only sendable values (bytes/path/key), never `this`.
    await Isolate.run(() async {
      final c = await VaultCrypto.encrypt(key, plain);
      await atomicWriteBytes(blobPath, c);
    });
    final item = VaultItem(
      id: id,
      name: name,
      sizeBytes: size,
      addedAt: DateTime.now(),
    );
    await _writeManifest([...await loadItems(), item]);
    try {
      await Isolate.run(() => secureDelete(sourcePath));
    } catch (_) {
      // Best effort: the copy is safely encrypted; a leftover original can be
      // removed by the user. Never mask a successful import over this.
    }
    return item;
  }

  /// Decrypts item [id] into [outputDir] under its original name (never
  /// overwriting — [uniqueDestination]). Returns the exported path.
  Future<String> exportTo(String id, String outputDir) async {
    final key = _requireKey();
    VaultItem? item;
    for (final e in await loadItems()) {
      if (e.id == id) item = e;
    }
    if (item == null) throw StateError('unknown vault item');
    final blob = _blobFile(id).readAsBytesSync();
    // PERFORMANCE: decrypt runs on a worker isolate (closure captures only
    // sendable bytes/key — never `this`).
    final plain = await Isolate.run(() => VaultCrypto.decrypt(key, blob));
    final target = uniqueDestination(outputDir, item.name);
    await atomicWriteBytes(target, plain);
    return target;
  }

  /// In-place view: decrypts to a plaintext file in a PRIVATE app directory
  /// (never the shared outputs folder) WITHOUT removing the vault copy. The
  /// file stays encrypted at rest; the plaintext exists only while viewing.
  /// Returns the decrypted path (name preserved — the viewer sniffs the type
  /// from the extension).
  Future<String> viewTo(String id, String viewsDir) async {
    final key = _requireKey();
    VaultItem? item;
    for (final e in await loadItems()) {
      if (e.id == id) item = e;
    }
    if (item == null) throw StateError('unknown vault item');
    final blob = _blobFile(id).readAsBytesSync();
    final plain = await Isolate.run(() => VaultCrypto.decrypt(key, blob));
    Directory(viewsDir).createSync(recursive: true);
    final target = uniqueDestination(viewsDir, item.name);
    await atomicWriteBytes(target, plain);
    return target;
  }

  /// Plaintext bytes of item [id] — for the OS save dialog (SAF) which takes
  /// bytes directly. The vault copy stays untouched.
  Future<Uint8List> plainBytesOf(String id) async {
    final key = _requireKey();
    final exists = (await loadItems()).any((e) => e.id == id);
    if (!exists) throw StateError('unknown vault item');
    final blob = _blobFile(id).readAsBytesSync();
    return Isolate.run(() => VaultCrypto.decrypt(key, blob));
  }

  /// Wipes every decrypted view file (called on hard lock / destroy — the
  /// plaintext must never outlive the unlocked session).
  void wipeViews(String viewsDir) {
    final dir = Directory(viewsDir);
    if (!dir.existsSync()) return;
    for (final e in dir.listSync()) {
      try {
        if (e is File) e.deleteSync();
      } catch (_) {
        // Best effort.
      }
    }
  }

  /// Secure-erases the encrypted blob and drops the manifest entry.
  Future<void> remove(String id) async {
    _requireKey();
    final items = [...await loadItems()]..removeWhere((e) => e.id == id);
    await _writeManifest(items);
    final blob = _blobFile(id);
    if (blob.existsSync()) await secureDelete(blob.path);
  }

  /// Destroys the whole vault: every encrypted blob, the manifest, and the
  /// wrapped key. Only succeeds with the correct [secret] — verified by
  /// unwrapping before anything is deleted. Returns false on wrong secret.
  Future<bool> reset(String secret) async {
    final wrappedB64 = await _keyStorage.read(_wrappedKeyStorageKey);
    if (wrappedB64 == null) return false;
    try {
      await VaultCrypto.unwrapKey(secret, base64Decode(wrappedB64));
    } on ArgumentError {
      return false;
    }
    _key = null;
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    await _keyStorage.delete(_wrappedKeyStorageKey);
    return true;
  }

  Future<void> _writeManifest(List<VaultItem> items) async {
    final key = _requireKey();
    final json =
        utf8.encode(jsonEncode([for (final i in items) i.toJson()]));
    final blob = await VaultCrypto.encrypt(
        key, Uint8List.fromList(json));
    await atomicWriteBytes(_manifestFile.path, blob);
  }

  String _newId() {
    final bytes = VaultCrypto.randomBytes(16);
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }
}
