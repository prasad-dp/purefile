import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Vault crypto (feature 14). Trust model, stated honestly:
/// • Files are encrypted with AES-256-GCM under a random 256-bit vault key.
/// • The vault key is wrapped (encrypted) with a key derived from the user's
///   secret via PBKDF2-HMAC-SHA256 (150k iterations, random 128-bit salt).
/// • Only the wrapped blob lives in secure storage; the plaintext vault key
///   never touches disk (memory only while unlocked).
/// • Biometrics gate the APP SESSION, they do not derive the key: removing
///   biometric enrollment must not lose data.
/// Everything here is pure Dart — unit-testable without a device.
class VaultCrypto {
  static final AesGcm _aes = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 150000,
    bits: 256,
  );

  static const int _saltLen = 16;
  static const int _macLen = 16;
  static const int _nonceLen = 12;
  static const int _keyLen = 32;

  /// Fresh random 256-bit vault key.
  static Uint8List newVaultKey() => randomBytes(_keyLen);

  /// Fresh random [length] bytes from the platform CSPRNG.
  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  /// Wraps [vaultKey] under a key derived from [secret].
  /// Returns one blob: salt(16) || cipherText(32) || mac(16) || nonce(12).
  static Future<Uint8List> wrapKey(String secret, Uint8List vaultKey) async {
    final salt = randomBytes(_saltLen);
    final wrapKeyBytes = await _deriveWrapKey(secret, salt);
    final box = await _aes.encrypt(
      vaultKey,
      secretKey: SecretKeyData(wrapKeyBytes),
    );
    final wrapped = BytesBuilder()
      ..add(salt)
      ..add(box.cipherText)
      ..add(box.mac.bytes)
      ..add(box.nonce);
    return wrapped.toBytes();
  }

  /// Unwraps the vault key. Throws [ArgumentError] when [secret] is wrong
  /// (GCM authentication failure) and [StateError] for malformed blobs.
  static Future<Uint8List> unwrapKey(String secret, Uint8List blob) async {
    if (blob.length != _saltLen + _keyLen + _macLen + _nonceLen) {
      throw StateError('malformed wrapped key');
    }
    final salt = blob.sublist(0, _saltLen);
    final cipherText = blob.sublist(_saltLen, _saltLen + _keyLen);
    final mac = blob.sublist(
        _saltLen + _keyLen, _saltLen + _keyLen + _macLen);
    final nonce = blob.sublist(_saltLen + _keyLen + _macLen);
    final wrapKeyBytes = await _deriveWrapKey(secret, Uint8List.fromList(salt));
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKeyData(wrapKeyBytes),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw ArgumentError('wrong secret');
    }
  }

  /// Encrypts file bytes under [vaultKey].
  /// Blob layout: cipherText || mac(16) || nonce(12).
  static Future<Uint8List> encrypt(Uint8List vaultKey, Uint8List plain) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKeyData(vaultKey));
    final blob = BytesBuilder()
      ..add(box.cipherText)
      ..add(box.mac.bytes)
      ..add(box.nonce);
    return blob.toBytes();
  }

  /// Decrypts a blob from [encrypt]. Throws [ArgumentError] on a wrong key
  /// or tampered data.
  static Future<Uint8List> decrypt(Uint8List vaultKey, Uint8List blob) async {
    if (blob.length < _macLen + _nonceLen) {
      throw ArgumentError('malformed encrypted blob');
    }
    final split = blob.length - _macLen - _nonceLen;
    final cipherText = blob.sublist(0, split);
    final mac = blob.sublist(split, split + _macLen);
    final nonce = blob.sublist(split + _macLen);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKeyData(vaultKey),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw ArgumentError('wrong key or tampered data');
    }
  }

  static Future<Uint8List> _deriveWrapKey(String secret, Uint8List salt) async {
    final key = await _kdf.deriveKey(
      secretKey: SecretKeyData(secret.codeUnits),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }
}
