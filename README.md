# PureFile — Offline File Toolbox

A private, fully offline file toolbox for Android & iOS (Flutter). PDF, image
and ZIP tools that never upload your files — **the release build has no
INTERNET permission, so the OS itself blocks network access.**

```
12 tools · encrypted vault · document scanner · on-device OCR
243 automated tests · zero network egress (proven) · 100% offline
```

## The tools

| Tool | What it does |
| --- | --- |
| Compress PDF | two-pass compression, never worse than the original |
| Merge PDF | PDFs + images in any order, reorderable |
| Split PDF | ranges, extract pages, every-N |
| Images → PDF | JPG/PNG/WebP/HEIC → one PDF (A4/fit) |
| PDF → Images | pages → JPG/PNG at chosen DPI |
| Compress Images | batch, presets, optional downscale |
| Convert Image | JPG ↔ PNG ↔ WebP |
| Create ZIP / Extract ZIP | zip-slip + zip-bomb protection |
| Document Scanner | camera → edge detect → perspective fix → clean PDF |
| OCR | searchable PDFs, all models bundled on-device |
| Sign & Stamp | draw once, place anywhere, flattened |
| Private Vault | AES-256-GCM at rest, biometric session gate, auto-lock |

Plus: share-sheet intake (send files from other apps), 7-day outputs history,
and a privacy dashboard showing processed counts, on-disk usage, and a local
crash log — with "0 uploaded" enforced by the OS.

## Build & run

```bash
cd purefile
flutter pub get
flutter run                      # debug (debug builds add INTERNET for hot reload — normal)
flutter build apk --release      # installable release APK
flutter build appbundle --release  # Play Store AAB
bash tool/egress_check.sh        # offline guarantee gate
dart run tool/generate_icons.dart  # regenerate all brand icons
flutter test                     # full suite
```

Requirements: Flutter 3.47+, JDK 17, Android SDK 36. Signing credentials live
in `android/key.properties` (gitignored — see `docs/store-listing.md`).

## Repository layout

```
lib/
  core/            the engine (no widgets): pure Dart, fully unit-tested
    tools.dart     tool registry (home grid source of truth)
    router.dart    go_router config (static routes precede the catch-all)
    jobs/          shared pipeline: pick → validate → isolate → result
    validation/    magic-byte + size validation, typed rejections
    file_io.dart   atomic writes, unique naming, secure delete
    pdf/  scan/  ocr/  image/  zip/   per-domain services
    vault/         crypto + encrypted store (pure Dart, no platform)
    history/  privacy/  share_intake/
  features/        screens (Riverpod), one folder per feature
  l10n/            app_en.arb — all strings
tool/              icon generator, egress checker
docs/              ALL documentation (see below)
test/              243 tests mirroring lib/
```

## Documentation index

| Doc | Contents |
| --- | --- |
| `docs/plan.md` | the 19-row build plan (features 0–18, all complete) |
| `docs/progress.md` | per-feature build log: decisions, gotchas, bug stories |
| `docs/requirements.md` | product requirements (F-numbers) |
| `docs/architecture.md` | layering rules, pipeline contract |
| `docs/design.md` | locked design language & palette |
| `docs/edge-cases.md` | the 51 edge cases the tools must survive |
| `docs/hardening.md` | F18 QA matrix: what's build-proven / test-proven / device-only |
| `docs/tester-guide.md` | **manual QA for testers**: per-feature scripts, device checklist, pass/fail template |
| `docs/maintenance.md` | **longterm maintainability**: module blast-radius map, dependency risks, upgrade procedures, gotchas |
| `docs/store-listing.md` | store copy, privacy policy text, data-safety answers |
| `docs/ci.md` | GitHub Actions APK builds + how to install locally |
| `docs/ui-polish.md` | F19 polish pass: size report, UX decisions |

## Quality gates (all green)

- `flutter analyze` — 0 issues
- `flutter test` — 243/243 (×3 soak, zero flakes)
- Release builds signed & jarsigner-verified
- Merged **release** manifest: no INTERNET (`tools:node="remove"` guards
  against dependency bleed)

## Privacy facts (factual to the build)

- No INTERNET permission in release builds — uploads are impossible
- No accounts, no analytics, no ads, no tracking SDKs
- Vault files AES-256-GCM encrypted; names live only in an encrypted manifest
- History records expire after 7 days; crash logs never leave the device
