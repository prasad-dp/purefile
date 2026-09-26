import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/errors.dart';
import 'package:purefile/core/vault/vault_store.dart';

void main() {
  late Directory root;
  late VaultStore vault;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pf_vault_test');
    vault = VaultStore(rootDir: root.path, keyStorage: InMemoryKeyStorage());
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Uint8List bytes(int length, [int seed = 7]) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (seed * i + 13) % 251]);

  /// True when [needle] appears as a contiguous run inside [haystack] — the
  /// correct "is the plaintext really gone" check (byte-frequency matchers
  /// are meaningless against kilobytes of ciphertext).
  bool containsSublist(List<int> haystack, List<int> needle) {
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  Future<String> writeSource(String name, List<int> content) async {
    final path = '${root.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(content);
    return path;
  }

  test('initialize + unlock round-trip; wrong secret refused', () async {
    expect(await vault.isInitialized(), isFalse);
    await vault.initialize('long enough secret');
    expect(await vault.isInitialized(), isTrue);
    expect(vault.isUnlocked, isTrue);

    vault.hardLock();
    expect(vault.isUnlocked, isFalse);

    expect(await vault.unlock('wrong secret'), isFalse);
    expect(vault.isUnlocked, isFalse);
    expect(await vault.unlock('long enough secret'), isTrue);
    expect(vault.isUnlocked, isTrue);
  });

  test('initialize rejects short secret and double init', () async {
    await expectLater(vault.initialize('short'), throwsArgumentError);
    await vault.initialize('long enough secret');
    await expectLater(vault.initialize('another long secret'), throwsStateError);
  });

  test('unlock before initialize throws StateError', () async {
    await expectLater(vault.unlock('whatever'), throwsStateError);
  });

  test('import encrypts on disk and secure-deletes the original', () async {
    await vault.initialize('long enough secret');
    final src = await writeSource('tax forms.pdf', bytes(4096, 3));
    final original = File(src);

    final item = await vault.importFile(src);
    expect(item.name, 'tax forms.pdf');
    expect(item.sizeBytes, 4096);
    expect(original.existsSync(), isFalse, reason: 'original must be erased');

    // Encrypted blob exists, and contains NO contiguous run of plaintext.
    final plain = bytes(4096, 3);
    final blob = File('${root.path}${Platform.pathSeparator}${item.id}.pfv');
    expect(blob.existsSync(), isTrue);
    expect(blob.lengthSync(), greaterThan(4096));
    expect(
      containsSublist(blob.readAsBytesSync(), plain.sublist(0, 64)),
      isFalse,
      reason: 'ciphertext must not embed the plaintext',
    );

    // Manifest must not contain the plaintext file name.
    final manifest =
        File('${root.path}${Platform.pathSeparator}${VaultStore.manifestName}');
    expect(
      containsSublist(manifest.readAsBytesSync(), 'tax forms.pdf'.codeUnits),
      isFalse,
      reason: 'manifest is encrypted — no readable file names',
    );
  });

  test('exportTo restores original bytes under the original name', () async {
    await vault.initialize('long enough secret');
    final content = bytes(2048, 11);
    final src = await writeSource('notes.txt', content);
    final item = await vault.importFile(src);

    final out = await vault.exportTo(item.id, root.path);
    expect(out.endsWith('notes.txt'), isTrue);
    expect(File(out).readAsBytesSync(), content);
  });

  test('loadItems and remove manage the manifest correctly', () async {
    await vault.initialize('long enough secret');
    final a = await vault.importFile(await writeSource('a.bin', bytes(64, 1)));
    final b = await vault.importFile(await writeSource('b.bin', bytes(64, 2)));

    var items = await vault.loadItems();
    expect(items.map((e) => e.id), containsAll([a.id, b.id]));

    await vault.remove(a.id);
    items = await vault.loadItems();
    expect(items.map((e) => e.id), [b.id]);
    expect(
      File('${root.path}${Platform.pathSeparator}${a.id}.pfv').existsSync(),
      isFalse,
    );
  });

  test('locked vault refuses operations', () async {
    await vault.initialize('long enough secret');
    vault.hardLock();
    expect(() => vault.loadItems(), throwsStateError);
    expect(() => vault.remove('x'), throwsStateError);
  });

  test('operations after hard re-unlock still work (key re-derived)',
      () async {
    final src = await writeSource('keep.bin', bytes(128, 5));
    await vault.initialize('long enough secret');
    final item = await vault.importFile(src);

    vault.hardLock();
    expect(await vault.unlock('long enough secret'), isTrue);
    expect((await vault.loadItems()).single.id, item.id);
    final out = await vault.exportTo(item.id, root.path);
    expect(File(out).readAsBytesSync(), bytes(128, 5));
  });

  test('oversized import throws FileTooLarge and writes nothing', () async {
    await vault.initialize('long enough secret');
    // Truncate-extend to one byte over the cap — instant on NTFS/ext4, no
    // real bytes are written, but lengthSync() reports the full size.
    final src = await writeSource('big.bin', const []);
    final raf = File(src).openSync(mode: FileMode.append);
    raf.truncateSync(VaultStore.maxImportBytes + 1);
    raf.closeSync();
    expect(File(src).lengthSync(), VaultStore.maxImportBytes + 1);

    final before = root.listSync().map((e) => e.path).toSet();
    await expectLater(vault.importFile(src), throwsA(isA<FileTooLarge>()));
    // Nothing new was created (no blob, no manifest update).
    expect(
      root.listSync().map((e) => e.path).where((p) => !before.contains(p)),
      isEmpty,
    );
    // And the oversized source survives (never consumed on failure).
    expect(File(src).existsSync(), isTrue);
  });

  test('blob names are random hex ids, not file names', () async {
    await vault.initialize('long enough secret');
    final a = await vault.importFile(await writeSource('secret-name.bin', bytes(32)));
    expect(a.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a.id, isNot(contains('secret')));
  });
}
