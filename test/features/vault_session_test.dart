import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/vault/vault_store.dart';
import 'package:purefile/features/vault/vault_session.dart';

late Directory root;
late ProviderContainer container;

VaultSession get session => container.read(vaultSessionProvider.notifier);
VaultSessionState get state => container.read(vaultSessionProvider);

void main() {

  /// Attaches a test session: temp dir, memory storage, controllable gate.
  ({VaultSession session, void Function(bool) setGate}) attachFresh({
    Duration soft = const Duration(minutes: 3),
    Duration hard = const Duration(minutes: 10),
  }) {
    var gateResult = true;
    session.attach(
      rootDir: root.path,
      keyStorage: InMemoryKeyStorage(),
      gate: () async => gateResult,
      biometricsProbe: () => true,
      softLockAfter: soft,
      hardLockAfter: hard,
    );
    return (
      session: session,
      setGate: (v) => gateResult = v,
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('pf_session_test');
    container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  test('uninitialized vault starts in setup phase and initializes', () async {
    attachFresh();
    await Future<void>.delayed(Duration.zero);
    expect(state.phase, VaultPhase.uninitialized);

    final ok = await session.initialize('long enough secret', 'long enough secret');
    expect(ok, isTrue);
    expect(state.phase, VaultPhase.unlocked);
  });

  test('initialize validation: short secret and mismatched confirm', () async {
    attachFresh();
    expect(await session.initialize('short', 'short'), isFalse);
    expect(state.lastError, isNotNull);

    expect(
      await session.initialize('long enough secret', 'different'),
      isFalse,
    );
    expect(state.phase, VaultPhase.uninitialized);
  });

  test('secret unlock: wrong refused, right accepted, phase flips', () async {
    attachFresh();
    await session.initialize('long enough secret', 'long enough secret');
    await session.lockNow(); // hard lock (soft defaults to false)

    expect(await session.unlockWithSecret('nope'), isFalse);
    expect(state.phase, VaultPhase.lockedHard);
    expect(state.lastError, 'Wrong secret');

    expect(await session.unlockWithSecret('long enough secret'), isTrue);
    expect(state.phase, VaultPhase.unlocked);
  });

  test('biometric unlock works while the key is soft-locked', () async {
    attachFresh();
    await session.initialize('long enough secret', 'long enough secret');
    await session.lockNow(soft: true);
    expect(state.phase, VaultPhase.lockedSoft);

    expect(await session.unlockWithBiometrics(), isTrue);
    expect(state.phase, VaultPhase.unlocked);
  });

  test('failed biometric gate stays soft-locked with an error', () async {
    final f = attachFresh();
    await f.session.initialize('long enough secret', 'long enough secret');
    await f.session.lockNow(soft: true);
    expect(state.phase, VaultPhase.lockedSoft);

    f.setGate(false);
    expect(await f.session.unlockWithBiometrics(), isFalse);
    expect(state.phase, VaultPhase.lockedSoft);
    expect(state.lastError, 'Authentication failed');
  });

  test('lockNow(soft) degrades to hard lock without biometrics', () async {
    var probe = false;
    session.attach(
      rootDir: root.path,
      keyStorage: InMemoryKeyStorage(),
      biometricsProbe: () => probe,
    );
    await Future<void>.delayed(Duration.zero);
    await session.initialize('long enough secret', 'long enough secret');

    await session.lockNow(soft: true);
    expect(state.phase, VaultPhase.lockedHard,
        reason: 'no biometrics → soft lock is meaningless');

    probe = true;
    expect(await session.unlockWithSecret('long enough secret'), isTrue);
    await session.lockNow(soft: true);
    expect(state.phase, VaultPhase.lockedSoft);
  });

  test('auto-lock: under soft threshold stays unlocked', () async {
    attachFresh();
    await session.initialize('long enough secret', 'long enough secret');

    session.onBackground();
    await session.onForeground(); // no elapsed time at all
    expect(state.phase, VaultPhase.unlocked);
  });

  test('auto-lock: past soft threshold re-gates with biometrics', () async {
    attachFresh(soft: const Duration(milliseconds: 1));
    await session.initialize('long enough secret', 'long enough secret');
    final itemsBefore = state.items.length;

    session.onBackground();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await session.onForeground();

    expect(state.phase, VaultPhase.unlocked,
        reason: 'gate stub returns true, so the vault re-opens');
    expect(state.items.length, itemsBefore);
  });

  test('auto-lock: past hard threshold requires the secret again', () async {
    attachFresh(hard: const Duration(milliseconds: 1));
    await session.initialize('long enough secret', 'long enough secret');

    session.onBackground();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await session.onForeground();

    expect(state.phase, VaultPhase.lockedHard);
    expect(state.lastError, isNull);
  });

  test('import/export/remove flow through the session and refresh items',
      () async {
    attachFresh();
    await session.initialize('long enough secret', 'long enough secret');

    final src = File('${root.path}${Platform.pathSeparator}doc.pdf');
    src.writeAsBytesSync(List.generate(512, (i) => i % 251));

    await session.importFile(src.path);
    expect(state.items, hasLength(1));
    expect(src.existsSync(), isFalse, reason: 'original secure-deleted');

    final outDir = Directory.systemTemp.createTempSync('pf_out_test');
    addTearDown(() => outDir.deleteSync(recursive: true));
    await session.exportTo(state.items.single.id, outDir.path);
    expect(File('${outDir.path}${Platform.pathSeparator}doc.pdf')
        .readAsBytesSync(),
        List.generate(512, (i) => i % 251));

    await session.remove(state.items.single.id);
    expect(state.items, isEmpty);
  });

  test('reset with wrong secret refuses; right secret wipes and re-initializes',
      () async {
    attachFresh();
    await session.initialize('long enough secret', 'long enough secret');
    final src = File('${root.path}${Platform.pathSeparator}f.bin');
    src.writeAsBytesSync([1, 2, 3]);
    await session.importFile(src.path);

    expect(await session.reset('wrong'), isFalse);
    expect(state.phase, VaultPhase.unlocked);

    expect(await session.reset('long enough secret'), isTrue);
    expect(state.phase, VaultPhase.uninitialized);
    expect(root.existsSync(), isFalse,
        reason: 'destroy removes the vault dir itself (blobs + manifest)');

    // A fresh vault can be created afterwards.
    expect(
      await session.initialize('another long secret', 'another long secret'),
      isTrue,
    );
  });

  test('clearError resets lastError', () async {
    attachFresh();
    expect(await session.unlockWithSecret('x'), isFalse);
    expect(state.lastError, isNotNull);
    session.clearError();
    expect(state.lastError, isNull);
  });
}
