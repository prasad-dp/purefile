# PureFile — Longterm Maintainability Guide

For anyone (human or AI) maintaining PureFile months from now: what each
module is, what breaks when you touch it, how to upgrade safely, and the
known gotchas that already cost time once.

Read order for a new maintainer: `README.md` → this file →
`docs/architecture.md` → `docs/progress.md` (per-feature decisions and
why-they're-that-way) → `docs/edge-cases.md` (the behavioral contract).

---

## 1. Module map & blast radius

Impact levels: 🔴 **core** (change = re-test everything) · 🟠 **sensitive**
(crypto/security/data-format — change with extreme care) · 🟡 **wide**
(many screens import it) · 🟢 **local** (self-contained feature).

| Module | Path | Impact | Notes |
| --- | --- | --- | --- |
| Tool registry | `lib/core/tools.dart` | 🟡 | Single source of truth for home grid, history labels, share chooser, privacy "top tools". Adding a tool = entry here + route + spec in the flow screen. Order matters for the grid. |
| Router | `lib/core/router.dart` | 🟡 | **Static routes (scan, sign, vault, /share, /privacy…) must be declared BEFORE `/tools/:toolId`** — go_router matches in order; F13 shipped a real bug from this. Regression-tested. |
| Shared pipeline | `lib/core/jobs/` (controller, task runner, copy-through) | 🔴 | Every tool flows through pick → validate → isolate → result. A change here affects all 10 generic-flow tools. History + usage counters are recorded here (`_recordHistory`). |
| Isolate runner | `lib/core/isolate_runner.dart` | 🔴 | Progress events, cooperative cancel + hard-kill, timeout, `RootIsolateToken` wiring (pdfx/ML Kit need `BackgroundIsolateBinaryMessenger.ensureInitialized` — F6 bug class). Any regression breaks every tool's cancel/progress. |
| Validation | `lib/core/validation/` + `lib/core/formats.dart` | 🔴 | Magic-byte sniffing, per-file/batch/storage pre-flight. The first line of defense for all input abuse. |
| File I/O | `lib/core/file_io.dart` | 🔴 | Atomic writes (temp+rename), unique naming, secure delete, orphan cleanup. Vault, ZIP, and every tool's output depend on it. Windows closed-handles quirk already fixed. |
| Vault crypto | `lib/core/vault/vault_crypto.dart` | 🟠 | **Data-format sensitive.** Wrapped-key blob layout `salt(16) ‖ cipher(32) ‖ mac(16) ‖ nonce(12)`; file blob `cipher ‖ mac ‖ nonce`; PBKDF2 150k iters. Never change layout/params — existing vaults become unreadable. Pure Dart, no platform. |
| Vault store | `lib/core/vault/vault_store.dart` | 🟠 | Manifest `manifest.pfv` = AES-GCM encrypted JSON (names never on disk); blobs `<32-hex-id>.pfv`. Import order: encrypt first, THEN 3-pass delete original (data-loss-window rule). 100 MB cap. |
| Vault session | `lib/features/vault/vault_session.dart` | 🟠 | Phase machine uninitialized/lockedHard/lockedSoft/unlocked + auto-lock timings. The soft-lock biometric short-circuit bug (F14) is regression-tested — don't re-gate on `isUnlocked`. |
| Theme | `lib/core/theme.dart` | 🟡 | `PfColors`, `PfMotion`, `PfHaptics`, `PfTheme`. Every screen imports it. Dark-mode category colors are chroma-lifted deliberately. |
| Shared widgets | `lib/widgets/ios_group.dart`, `hero_header.dart`, `file_chip.dart`, `tool_card.dart` | 🟡 | `PfGroupItem` hairline logic depends on first/last flags — re-check every list after edits. |
| PDF services | `lib/core/pdf/` | 🟠→🟢 | Compress/merge/split/images-to-pdf/to-images/stamp/ocr. Merge/split/stamp/OCR share the template + per-page-section pattern with the landscape `orientation`-before-`size` quirk — change one, re-run all their tests. OCR's invisible-text layer (alpha-0 brush) is the searchable-PDF keystone (F12 keystone test). |
| OCR bridge | `lib/core/ocr/mlkit_ocr.dart` + ocr service injections | 🟢 | Device-only code behind `PageRecognizer`/`PageRaster` typedefs — unit tests inject stubs; pdfx/ML Kit cannot run in plain test isolates. Keep the injection seams. |
| Scan | `lib/core/scan/` | 🟢 | Pure Dart (quad detect, homography warp, enhancement) + thin camera front-end. Gallery import runs the same pipeline as the camera. |
| ZIP service | `lib/core/zip_service.dart` | 🟠 | Zip-slip two-phase validation (hostile archive writes NOTHING) and zip-bomb pre-inflation check are security features — their tests assert before/after directory snapshots. Don't "simplify". |
| Share intake | `lib/core/share_intake/share_intake.dart` | 🟢 | `eligibleToolIds()` runs the REAL validator/specs — chooser can never offer a rejecting tool. `toolUiSpec()` is the shared spec source (extracted in F16). |
| History | `lib/core/history/history_store.dart` | 🟢 | Key `pf.history.v1`, 7-day purge (injected clock), cap 400, orphan cleanup. Records only — never deletes user files. |
| Privacy/usage | `lib/core/privacy/` | 🟢 | `pf.usage.*` counters serialized through one async queue (lost-update test); crash ring buffer cap 100, append never throws. |
| Tool flow screen | `lib/features/tools/tool_flow_screen.dart` | 🟡 | One screen drives 10 tools via `ToolUiSpec` + options cards. Adding a tool option = spec + options state + card. |
| Screens (per feature) | `lib/features/*/` | 🟢 | Self-contained Riverpod screens; F19b iOS-craft styling via shared widgets. |
| Appearance | `lib/core/appearance.dart` + `lib/widgets/theme_toggle.dart` | 🟡 | Theme-mode state + persistence. MaterialApp watches `themeModeProvider`; the startup restore gate must stay BEFORE share-intake start in app.dart (launch brightness). `nextThemeMode` is shared by all controls — don't fork the cycle. |

### Change-safety rules

1. **Anything in `lib/core/`**: run the full `flutter test` — 243 tests mirror
   lib/ almost 1:1. Never commit with a red suite.
2. **Vault or ZIP security code**: read the relevant `hardening.md` section
   first; the tests encode attack scenarios, not just behavior.
3. **Pipeline/isolate changes**: manually cancel a long job on device —
   cancel-cleans is contract #4. ISOLATE RULE: anything sent to
   `runJob`/`Isolate.spawn`/`Isolate.run` must close over locals and
   top-level functions ONLY — never a controller/State tear-off or `this.*`
   field reads (device-only failure; host tests can't reproduce it).
4. **Router changes**: add the static-route-precedence test case if you add
   any static route.
5. **After ANY dependency change**: run `tool/egress_check.sh` (see §4).

---

## 2. Dependency risk table

| Dependency | Pin | Why it's risky / pinned |
| --- | --- | --- |
| `receive_sharing_intent` | **1.8.1 exact** | 1.9.0 requires compileSdk 37; project is on 36 (AAR metadata check fails). Dart API identical in 1.8.1. Its Gradle module ships Java 11 — pinned to JVM 11/11 in `android/build.gradle.kts` **scoped to `project.name == "receive_sharing_intent"`** (an unscoped pin broke :app's Java 17). Revisit both pins together when upgrading to compileSdk 37. |
| `syncfusion_flutter_pdf` | ^34.2.9 | Powers compress/merge/split/stamp/OCR text layer. Encrypted PDFs throw ArgumentError-style **Errors** (not Exceptions) — classification is message-based; verify after bumps. Embeds timestamps in xref IDs (byte sizes wobble a few bytes — known test-flake source, see §7). License terms for commercial use — check when updating. |
| `image` | **4.9.0 exact** | Extremely lenient decoders (junk "decodes" via TGA fallback; routing follows filename extension). Fixtures and typed-error tests depend on these quirks. `encodeJpg` (not `encodeJpeg`); throws RangeError on 0-byte input (normalized upstream). |
| `pdfx` | ^2.11.0 | Platform-channel renderer — cannot run in unit isolates; tests inject a stub `PageRenderer`. Password support is web-only (typed limitation surfaced to users). Needs `RootIsolateToken` in workers. |
| `google_mlkit_text_recognition` | ^0.17.1 | Models bundled in `android/app/build.gradle.kts` (5 × 16.0.1 ≈ 25 MB APK bulk — deliberate, offline promise). CJK/Devanagari are `compileOnly` upstream; our block makes them bundled. **No Arabic model exists.** Bumping models = size jump + manifest re-verify. |
| `camera` + `camera_android_camerax` | ^0.12.1 / ^0.7.4+8 | CameraX lineage; keep the pair version-compatible. Emulator has no camera — device-only verification. |
| `local_auth` | ^3.0.2 | Requires `FlutterFragmentActivity` (MainActivity.kt) — reverting to FlutterActivity breaks biometrics silently. Biometrics gate the session only, never derive the key. |
| `flutter_secure_storage` | ^10.3.4 | Holds the wrapped vault key. Device-only behavior (Keystore/Keychain). |
| `cryptography` | ^2.9.0 | PBKDF2/AES-GCM. API gotchas recorded in progress.md (SecretKeyData, SecretBox, BytesBuilder cascade). |
| `archive` | **4.0.9 exact** | Zip-slip/bomb logic depends on `size` being pre-inflation metadata (source-verified for this version). Duplicate identical names collapse at decode; case-clash is the testable case. |
| `go_router` | ^16.3.0 | Route-order matching semantics underpin the static-route rule. |
| `file_picker` / `open_filex` / `share_plus` / `path_provider` / `shared_preferences` | standard | Low risk; shared_preferences carries `pf.history.v1` + `pf.usage.*` (migration notes §5). |
| Flutter SDK | 3.47.5 stable | Project SDK ^3.13.0. Upgrade via §3 procedure; `onReorderItem` API (3.47) used by merge/images-to-pdf/scan lists. |

### Adding a new dependency — checklist

1. Does it request `android.permission.INTERNET` (or transitively)? If yes,
   **don't add it**, or add the `tools:node="remove"` audit in
   `android/app/src/main/AndroidManifest.xml` and re-verify the merged
   release manifest.
2. `flutter pub get` → `flutter analyze` → `flutter test` (full 243) →
   `bash tool/egress_check.sh` → release build.
3. Record the pin + reason in this table and in `docs/progress.md`.

---

## 3. Upgrade procedures

### Flutter SDK upgrade

1. Read the release notes for breaking changes, especially: go_router, camera,
   and Material APIs used by the F19b widget set.
2. Install the new Flutter alongside (don't delete the working one).
3. `flutter --version` → `flutter pub get` → `flutter analyze` →
   `flutter test` (full suite, expect fallout at go_router/camera first).
4. `flutter build apk --debug` first (fast), then release AAB.
5. Device smoke test per `docs/tester-guide.md` §3 (app shell) + one tool.
6. Update the version note in `pubspec.yaml` comment/README.

### Dependency bump checklist (run in this order, stop on first red)

```bash
flutter pub get
flutter analyze          # must be 0 issues
flutter test             # must be 243/243
bash tool/egress_check.sh   # MUST pass — the offline guarantee gate
flutter build apk --release --split-per-abi
```

Plus, per-target:

- **ML Kit model bump**: size jump is expected (+25 MB class); re-grep the
  merged release manifest for INTERNET; device-test OCR in airplane mode.
- **receive_sharing_intent / compileSdk bump**: un-pin 1.8.1 AND revisit the
  scoped JVM pin in `android/build.gradle.kts` TOGETHER; expect the
  "Inconsistent JVM-target" failure class (§7).
- **syncfusion bump**: re-verify encrypted-PDF classification and the
  never-worse round-trip test (xref timestamp wobble).
- **image / archive exact pins**: only bump deliberately — decoder quirks and
  pre-inflation `size` semantics are load-bearing for tests and security.
- **local_auth / MainActivity**: never let MainActivity.kt revert to
  FlutterActivity; biometrics die silently.

### Regenerating brand assets

```bash
dart run tool/generate_icons.dart
```

Emits all Android adaptive/legacy + iOS AppIcon.appiconset from the master
`assets/brand/icon_1024.png`. Re-run after changing the mark; verify a debug
build so new res XMLs get validated.

### Release procedure (per release)

1. Full gates (analyze · test · egress · builds).
2. `bash tool/egress_check.sh` on the merged release manifest output.
3. Bump `version:` in pubspec (keep `+N` build number monotonic).
4. Build AAB with the REAL keystore (machine with `key.properties`),
   jarsigner-verify.
5. Play pre-launch report (device-only row D6 in hardening.md).
6. Device QA pass: hand `docs/tester-guide.md` to a tester; minimum scope
   = §3 shell + one tool per category + §5 vault + §8 share-sheet.

---

## 4. The offline guarantee (how to keep it true)

The promise is enforced at three layers; all three must stay green:

1. **Source scan** — `tool/egress_check.sh` finds zero networking primitives
   in `lib/` (HttpClient/http/Socket).
2. **Manifest strip** — `<uses-permission android:name="android.permission.INTERNET"
   tools:node="remove"/>` in `android/app/src/main/AndroidManifest.xml`.
   Manifest merger union-wins by default, so a transitive dependency CAN
   re-introduce INTERNET (this actually happened via ML Kit/GMS — F18) — the
   remove-rule is the only guarantee.
3. **Merged-manifest grep** — also in egress_check.sh: builds/parses the
   merged release manifest and fails on `INTERNET`.

**Never** delete or weaken the `tools:node="remove"` rule. Debug builds add
INTERNET for hot reload (Flutter injects it) — debug-only by design, never
shipped; egress_check documents this exemption.

If egress_check fails after a dependency change: the new dependency (or
something transitive) requests INTERNET. That is normally FINE — the strip
still removes it — but you must re-verify the merged release manifest is
clean before shipping (run the release build, grep the manifest under
`build/app/intermediates/merged_manifests/release/`), and record the finding
in progress.md.

---

## 5. Data formats & migration notes

Local-only data. Never change layouts casually — existing installs must keep
reading their data.

| Data | Key/Format | Rules |
| --- | --- | --- |
| Outputs history | SharedPreferences `pf.history.v1` | JSON list, newest-first, 7-day auto-purge (injected clock), cap 400, orphan cleanup, corrupt JSON → empty list. Bump the version suffix only with a reader that understands both formats. |
| Usage counters | SharedPreferences `pf.usage.*` | Counters + bytes + per-tool map; one async queue serializes mutations; reset supported. Same versioning rule. |
| Theme mode | SharedPreferences `pf.appearance.mode` | "system" / "light" / "dark"; read into `themeModeProvider` at startup (before first frame), written by any theme control. Unknown values → system. Trivial format, but keep the string names stable — `ThemeMode.name` is the writer. |
| Crash log | file (ring buffer, cap 100) | `<iso8601> <source>: <flat message>`; malformed lines skipped; append never throws. |
| Vault wrapped key | secure_storage; blob `salt(16)‖cipher(32)‖mac(16)‖nonce(12)` | PBKDF2-HMAC-SHA256 150k iters. **Never change** layout or iteration count — unreadable vaults. Forgotten secret = unrecoverable by design. |
| Vault manifest | `documents/vault/manifest.pfv` | AES-GCM encrypted JSON of entry names; file names never on disk in plaintext (tested via contiguous-sublist check). |
| Vault blobs | `documents/vault/<32-hex-id>.pfv` | `cipher‖mac‖nonce`; ids not names. Import = encrypt → atomic write → 3-pass secure-delete original. 100 MB cap. |
| Outputs | app documents dir | Atomic temp+rename, `uniqueDestination` (file AND directory collisions), auto-numbered `name (2).ext`. |
| Scan scratch | numbered `page_NN.jpg` | Wiped on screen open; never user data. |

Migration principles: additive readers first (read old + new), only then
writers; in-place re-encryption requires a verified round-trip first; write a
migration test with a fixture of the OLD format before touching any of these.

---

## 6. Performance & size envelope

Known-good envelope (regression-notice, not a hard budget):

- Per-ABI release APKs: **29.5 / 35.7 / 37.7 MB** (arm32/arm64/x86_64) with
  `--split-per-abi --obfuscate --split-debug-info`; AAB 78.3 MB ⇒ Play
  downloads ≈ 30–36 MB.
- The bulk is 5 bundled OCR models (deliberate — offline promise). If size
  must shrink, that's the only real lever, and it trades against the
  airplane-mode OCR guarantee.
- Test suite runtime class: 243 tests; 3× soak green. New core tests should
  stay in the instant-fixture style (truncate-extend trick for large-file
  fixtures).

Watch for regressions: a dependency adding a native .so per ABI (e.g. a new
media library) can double APK size — measure after adding any plugin with
native code.

---

## 7. Troubleshooting — known gotchas (all previously bit us)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Gradle: "Inconsistent JVM-target" on :app | The receive_sharing_intent JVM pin was applied to ALL subprojects | Keep it **scoped**: `if (project.name == "receive_sharing_intent")` in `android/build.gradle.kts` |
| Gradle script compile error on key.properties reading | Gradle Kotlin DSL needs `import java.util.Properties` at the top of `android/app/build.gradle.kts` | Add the import (it's there — restore if a refactor dropped it) |
| Flutter: "failed to strip debug symbols" during release build | NDK strip missing on the machine | WARNING only — the AAB/APK lands fine; ignore or install NDK |
| `flutter test` flake in compress round-trip | syncfusion embeds timestamps in xref IDs → byte sizes wobble ±few bytes flipping the never-worse threshold | Tests assert the stable contract (output ≤ input, kept-original ⇒ byte-identical) — don't tighten to exact sizes |
| Junk image "decodes" in a test you expected to fail | image-4.9 leniency: no-magic TGA fallback, filename-based decode routing | Only reliably undecodable fixture: 0-byte file whose extension routes to a magic-checking decoder (`junk.jpg`) |
| Encrypted-PDF test expects an Exception | syncfusion throws ArgumentError-style **Errors** | Classification is message-based — see pdf services |
| pdfx/ML Kit crash in unit tests | Platform channels in plain isolates | Tests inject stub `PageRenderer`/`PageRecognizer`; workers need `RootIsolateToken` + `BackgroundIsolateBinaryMessenger.ensureInitialized` |
| Biometrics dead after a mainactivity refactor | FlutterActivity instead of FlutterFragmentActivity | Keep `FlutterFragmentActivity()` in MainActivity.kt |
| **"object is unsendable — Class: _AsyncCompleter / WidgetsFlutterBinding…" on device at Start** | Any anonymous closure `(ctx) => ...` created inside an instance method (e.g. `start()`) captures that method's context frame (`this`, `_AsyncCompleter`, Riverpod ref), dragging watched widget elements (RenderParagraph, WidgetsFlutterBinding) into `Isolate.spawn`/`Isolate.run` | Pass top-level function tear-offs (`entry: runToolTask`) + sendable `args` directly to `runJob`, or wrap `Isolate.run` calls in top-level functions (`runStampInIsolate`, `runScanPageInIsolate`). Never construct a closure inside a class instance method when spawning isolates. Regression-guarded in `test/core/isolate_spawn_safety_test.dart` and `test/core/isolate_runner_test.dart` |
| Share intent dead after dependency change | receive_sharing_intent 1.9.0 + compileSdk 37 mismatch | Stay on 1.8.1 until compileSdk 37; then revisit JVM pin together |
| Vault key/params change considered | Breaks existing vaults | Never change blob layout/PBKDF2 iters (§5) |
| CI red on INTERNET grep | Dependency re-introduced INTERNET into the merged manifest | Check the `tools:node="remove"` rule is intact; re-verify merged manifest; record in progress.md |
| Router: tool card opens the generic flow instead of the custom screen | Static route declared AFTER `/tools/:toolId` | Static routes first (scan/sign/vault, /share, /privacy); add a precedence test |
| Stale Gradle daemon locks Kotlin caches on Windows | Killed build left a daemon | Kill the daemon; `kotlin.incremental=false` + in-process strategy already set in gradle.properties |
| Hundreds of `pf_*` dirs in Windows Temp | Test temp dirs from suite runs | Harmless; cleanup command below — only with owner approval |

Windows Temp cleanup (630 orphan `pf_*` dirs as of this writing — **ask the
owner first**):

```bash
rm -rf /c/Users/prasa/AppData/Local/Temp/pf_*
```

---

## 8. Where everything lives (quick index)

- Docs: `docs/` — plan, progress (per-feature log), requirements, architecture,
  design, edge-cases (51 cases), hardening (QA matrix), tester-guide (manual
  QA), maintenance (this file), store-listing, ci, ui-polish.
- Gates: `tool/egress_check.sh` (offline proof), `tool/generate_icons.dart`,
  `.github/workflows/android.yml` (CI: analyze → test → egress → release APKs
  → manifest grep gate).
- CI artifacts: arm64 / arm32 / universal release APKs per run — testers use
  `docs/tester-guide.md` §1.
- Signing: `android/app/pf-release.keystore` + `android/key.properties`
  (gitignored; loss = cannot update the Play listing — back up). Fresh clones
  fall back to debug signing so they still build.
