# CI — Android APK builds

`.github/workflows/android.yml` builds a **release APK on every push/PR**
(and on demand via *Run workflow*), so you can sideload and test locally.

## What it runs, in order

1. `flutter pub get` + `flutter gen-l10n`
2. `flutter analyze` — fails the build on any issue
3. `flutter test` — the full 243-test suite
4. `tool/egress_check.sh` — source-level network-egress scan
5. `flutter build apk --release --split-per-abi`
6. **Offline guarantee gate**: greps the merged release manifest for
   `INTERNET` — fails the workflow if a dependency ever sneaks it back in
7. Uploads three artifacts

## Getting the APK onto your phone

1. Open the repo on GitHub → **Actions** → latest *Android APK* run
2. Scroll to **Artifacts** → download:
   - `purefile-arm64-apk` — every modern phone (use this one)
   - `purefile-arm32-apk` — older 32-bit devices
   - `purefile-x86_64-apk` — emulators and ChromeOS
3. Unzip, copy the `.apk` to the phone, open it, allow "install unknown
   apps" when prompted.

Artifacts are kept per-run; retention follows your repo's default (90 days).

## Signing note

The workflow machine has no `key.properties`/keystore (they're gitignored on
purpose), so Gradle falls back to **debug signing** — the build is still a
full release build (AOT, obfuscated-size, no INTERNET), just signed with the
debug key. Perfectly fine for local testing. Play Store uploads still use
the real keystore from a machine that has it (see `docs/store-listing.md`).

If you ever want CI to sign with the real key: store `key.properties` + the
keystore as base64 in repository secrets and decode them in a step before
the build — not enabled by default to keep secrets out of the repo.

## Also verify locally

```bash
flutter analyze && flutter test
bash tool/egress_check.sh
flutter build apk --release --split-per-abi
```
