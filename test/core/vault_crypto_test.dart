import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/vault/vault_crypto.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final secret = 'correct horse battery staple';

  test('round-trips a wrapped vault key', () async {
    final blob = await VaultCrypto.wrapKey(secret, key);
    expect(blob.length, 16 + 32 + 16 + 12);
    final unwrapped = await VaultCrypto.unwrapKey(secret, blob);
    expect(unwrapped, key);
  });

  test('wrong secret throws ArgumentError', () async {
    final blob = await VaultCrypto.wrapKey(secret, key);
    expect(
      () => VaultCrypto.unwrapKey('wrong', blob),
      throwsArgumentError,
    );
  });

  test('tampered wrapped blob throws ArgumentError', () async {
    final blob = await VaultCrypto.wrapKey(secret, key);
    blob[20] ^= 0xFF;
    expect(
      () => VaultCrypto.unwrapKey(secret, blob),
      throwsArgumentError,
    );
  });

  test('malformed wrapped blob throws StateError', () {
    expect(
      () => VaultCrypto.unwrapKey(secret, Uint8List(3)),
      throwsStateError,
    );
  });

  test('round-trips file bytes; blobs differ per call (fresh nonce)',
      () async {
    final plain = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final a = await VaultCrypto.encrypt(key, plain);
    final b = await VaultCrypto.encrypt(key, plain);
    expect(a.length, plain.length + 16 + 12);
    expect(a, isNot(b));
    expect(await VaultCrypto.decrypt(key, a), plain);
    expect(await VaultCrypto.decrypt(key, b), plain);
  });

  test('tampered file blob throws ArgumentError', () async {
    final blob = await VaultCrypto.encrypt(key, Uint8List.fromList([1, 2, 3]));
    blob[0] ^= 0xFF;
    expect(() => VaultCrypto.decrypt(key, blob), throwsArgumentError);
  });

  test('wrong key on file blob throws ArgumentError', () async {
    final blob = await VaultCrypto.encrypt(key, Uint8List.fromList([1, 2, 3]));
    final otherKey = Uint8List(32);
    expect(() => VaultCrypto.decrypt(otherKey, blob), throwsArgumentError);
  });

  test('empty file encrypts/decrypts', () async {
    final blob = await VaultCrypto.encrypt(key, Uint8List(0));
    expect(blob.length, 16 + 12);
    expect(await VaultCrypto.decrypt(key, blob), Uint8List(0));
  });

  test('vault keys are random and 256-bit', () {
    final a = VaultCrypto.newVaultKey();
    final b = VaultCrypto.newVaultKey();
    expect(a.length, 32);
    expect(a, isNot(b));
  });
}
