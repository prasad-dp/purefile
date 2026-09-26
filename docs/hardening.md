# Hardening & QA matrix (Feature 18 / plan row 18)

Status legend: **[T]** = enforced by an automated test (file noted) ·
**[B]** = proven by a release-build artifact check · **[D]** = device-only,
requires hardware (listed with what to check) · **[X]** = known limitation,
documented and intentional.

## 1. Offline guarantee (the core promise)

| Check | Status | Evidence |
| --- | --- | --- |
| No `INTERNET` in merged **release** manifest | **[B]** | `tools:node="remove"` in the app manifest strips any dependency's request; `grep` on `build/.../release/processReleaseManifest/AndroidManifest.xml` is clean |
| Debug builds have INTERNET | **[X]** | Flutter adds it for hot reload — debug-only by design, never shipped |
| No network primitives in Dart source | **[B]** | `tool/egress_check.sh` — zero `HttpClient`/`http.*`/`Socket` in `lib/` |
| Release APK + AAB rebuild clean after the strip | **[B]** | `app-release.apk` (95.3 MB) and `app-release.aab` (82 MB) built with the strip in place |
| ML Kit models bundled, no Play Services download | **[B]** | `android/app/build.gradle.kts` bundles all five script models 16.0.1 (Arabic: see plan correction in progress.md F12 — ML Kit has no Arabic model) |
| Privacy dashboard says only what's true | **[T]** | counters come from `usage_store` (local SharedPreferences), "0 uploaded" is enforced by the OS-level fact above |

## 2. Input abuse (edge cases #1–#9, #25)

| Check | Status | Evidence |
| --- | --- | --- |
| Zero-byte file | **[T]** | rejected by validator (`CorruptedFile`); image/PDF decoders normalize the image-4.9 RangeError throw to typed errors |
| Random noise with a real extension | **[T]** | magic-vs-extension check rejects (`CorruptedFile` / `UnsupportedFormat`) |
| Truncated PDF (valid header, no body) | **[T]** | passes the fast magic gate **by design**, then the tool's probe layer rejects with `CorruptedFile` and writes nothing (`hardening_test.dart`) |
| PNG signature + junk | **[T]** | rejected at validation |
| Encrypted PDF | **[T]** | `PasswordRequired` (probe-classified before work, per tool) |
| Out-of-range page selections | **[T]** | clamped or `UnsupportedFormat` with nothing written |
| Garbage through the vault | **[T]** | vault is a storage box, not a format gate — round-trips bytes exactly |
| Blank page OCR | **[T]** | `noText` flag → outputs still produced + warning, not an error |

## 3. Filenames & filesystem (#33, vault + outputs)

| Check | Status | Evidence |
| --- | --- | --- |
| `report.pdf` collision → `report (2).pdf` | **[T]** | `file_io_test` (also treats directories as taken) |
| Emoji / CJK / Cyrillic / long names | **[T]** | `hardening_test.dart`: `报表 📊.pdf`, `отчёт годовой.png`, `naïve résumé — final (v2).zip`, `emoji-🚀💥-name.jpg`, 180-char names — vault import preserves name, export restores it exactly |
| Parallel atomic writes | **[T]** | 12 concurrent `atomicWriteBytes` — no corruption, no surviving `.pf-tmp` |
| Kill mid-write | **[T]** | temp-then-rename contract; `cleanupTempFiles` removes orphans, never real files |
| Storage exhaustion | **[T]** | `validateBatch` → `InsufficientStorage` typed error (skipped only where the OS query is unavailable) |
| Vault original erasure | **[T]** | 3-pass overwrite after the encrypted copy is durable — no data-loss window; failure to erase never masks a successful import |

## 4. Archive attacks (F9)

| Check | Status | Evidence |
| --- | --- | --- |
| Zip-slip (`../../etc/passwd` style) | **[T]** | two-phase extract validates ALL entry paths before any disk I/O → `ZipSlipDetected` |
| Zip bomb | **[T]** | declared-size pre-inflation check, 20× ratio, 100 MB floor / 1 GB ceiling → `ZipBombDetected` |
| Case-clash entries (`a.txt` / `A.txt`) | **[T]** | deduped on extract |

## 5. Crypto (F14)

| Check | Status | Evidence |
| --- | --- | --- |
| Wrong secret / tampered blob / malformed blob | **[T]** | `vault_crypto_test.dart` — `ArgumentError` / `StateError`, never a crash |
| File names never on disk in plaintext | **[T]** | manifest is AES-GCM encrypted; contiguous-sublist check on raw bytes |
| Forgotten secret | **[X]** | unrecoverable **by design**, stated in setup copy |
| Biometric removal loses data | **[X]** | impossible — biometrics gate the session, never derive the key |
| Soft-lock bypass | **[T]** | the `isUnlocked` short-circuit bug is fixed + regression-tested (`vault_session_test.dart`) |
| Destroy vault with wrong secret | **[T]** | verified by unwrap BEFORE any deletion |

## 6. Stability

| Check | Status | Evidence |
| --- | --- | --- |
| Full suite ×3 (soak) | **[B]** | 243/243, three consecutive runs, zero flakes |
| Crash safety net | **[T]** | FlutterError + PlatformDispatcher hooks → ring buffer (cap 100, crash-proof appends, malformed-line tolerant) |
| Router shadowing regressions | **[T]** | static routes before `/tools/:toolId` asserted (scan, sign, vault) |
| Missing ProviderScope | **[T]** | fixed in F16; scaffold tests pump through the scope |

## 7. Device-only pass (run on hardware before tagging a release)

- **[D]** Camera capture → scan pipeline (emulator has no camera; gallery-import path is unit-covered)
- **[D]** ML Kit recognition quality on real photographed pages (Latin + CJK + Devanagari)
- **[D]** Biometric prompt (fingerprint/face), auto-lock on real backgrounding (3/10 min)
- **[D]** flutter_secure_storage backed by real Keystore/Keychain
- **[D]** Share-sheet: send 1 file and a multi-selection from Files/Photos into PureFile
- **[D]** Play Store pre-launch report against the AAB

## 8. Known limitations (documented, intentional)

- **[X]** Vault imports capped at 100 MB (memory-buffered encryption)
- **[X]** Vault blobs are encrypted but the vault dir lives in app-private storage — a rooted device is out of threat model
- **[X]** Arabic OCR: ML Kit has no Arabic model (plan correction logged at F12)
- **[X]** PDF → Images needs pdfx (platform channels) — not unit-testable, injected-renderer tests cover the logic
- **[X]** `flutter` may print "failed to strip debug symbols" on machines without NDK strip — warning only; the AAB/APK land fine
