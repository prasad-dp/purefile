# PureFile — Product Plan v1.0

> **PureFile** is a private, offline file toolbox for Android + iOS: PDF tools, image tools, ZIP tools, document scanner, OCR, signature, and an encrypted vault. Everything runs **on the device** — no cloud, no uploads, no accounts, fully functional in airplane mode.
>
> **Read this first if you are continuing the build** (human or AI): see `progress.md` for current state, `architecture.md` for structure, `design.md` for UI rules, `requirements.md` for behavior contract, `edge-cases.md` for the QA contract.

## Product decisions (locked)

| Decision | Value |
|---|---|
| Name | PureFile (app id `com.purefile.app` — confirm before store submission; permanent after) |
| Platforms | Android first release; iOS build-ready throughout, release after Android |
| Framework | Flutter (single Dart codebase, Material 3) |
| Processing | 100% on-device. No INTERNET permission on Android. No cloud APIs ever for core features. |
| Business model | Free at launch. Phase 2 optional: AdMob + PureFile Pro subscription (no ads, 200 MB file cap, HD output). Network code must stay isolated in one optional module so a "pure offline" flavor is trivial. |
| Min devices | Android 7.0 (API 24)+, incl. 32-bit (armeabi-v7a) and 1–2 GB RAM phones. iOS 15+ later. |
| File limits | 50 MB per file, 30 files / 100 MB per batch (all in `core/constants.dart`, tunable; Pro may raise) |

## Scope honesty (repeat to stakeholders)
"Any file → any file" offline is impossible (e.g. DOCX→PDF requires a Word-compatible renderer). PureFile ships the conversions that work reliably on-device and **hides unsupported pairs in the UI** rather than failing at runtime.

## Feature list — MVP

### Core tools
| Tool | In → Out | Options |
|---|---|---|
| Compress PDF | PDF → smaller PDF | 3 quality levels; shows % saved; never worse than input |
| Merge PDF | 2+ PDFs (+ images) → one PDF | reorder, mixed inputs, duplicate names handled |
| Split PDF | PDF → multiple PDFs | custom ranges / extract pages / every-N-pages |
| Images → PDF | JPG/PNG/WebP/HEIC → one PDF | reorder, A4/Letter/fit-page, EXIF orientation honored |
| PDF → Images | PDF → JPG or PNG per page | page range, DPI preset (1x/2x/300), size-growth warning |
| Compress Images | batch → smaller images | quality slider, before/after sizes, strip EXIF/GPS default ON |
| Convert Image | JPG ↔ PNG ↔ WebP (HEIC read) | target format, background color for transparency |
| ZIP Create | any picked files → one ZIP | UTF-8 names (emoji/Cyrillic safe) |
| ZIP Extract | ZIP → files | in-app archive browser, nested ZIPs |

### Differentiators (the moat)
| Feature | Detail |
|---|---|
| Document Scanner | camera → auto edge-detect, deskew, shadow clean → PDF; multi-page; no watermark, no cloud |
| OCR | scanned PDF/image → searchable PDF + copyable text. On-device ML Kit with **models bundled in the APK**; Latin/CJK/Devanagari/Arabic; graceful typed error on devices without Play Services |
| Signature & Stamp | draw signature once → place/resize on pages → flatten & save |
| PureFile Vault | biometric + PIN fallback, AES-GCM encryption at rest, auto-lock, secure delete, encrypted export/import for phone migration |
| Privacy Dashboard | "X files processed · 0 uploaded", proof of no INTERNET permission, crash-log viewer |
| Share-sheet | compress/convert directly from the Android share menu (50 MB guard applies) |

### Phase 2 (post-launch)
Offline AI chat-with-PDF (on-device LLM) · page organizer (thumbnail reorder/rotate/delete) · PDF password protect/unlock · watermarks · extract images from PDF · metadata editor · AdMob + Pro.

## Build order — one feature at a time (hard rule)
Each feature follows the full cycle and is **fully functional + tested before the next starts**:
build → unit + edge-case tests → `flutter analyze` 0 issues → `flutter test` green → `flutter build apk --debug` compiles → verify on device → update `progress.md` → commit.

| # | Feature | Definition of "functional" |
|---|---|---|
| 0 | Docs + scaffold | project builds; theme/router/home grid/onboarding render; docs complete |
| 1 | Shared pipeline | pick → validate (size/magic/encryption/storage) → options → isolate (progress/cancel/timeout) → result (share/save); typed errors surfaced |
| 2 | Compress PDF | works + edge tests + honest "not smaller" behavior |
| 3 | Merge PDF | reorder, mixed PDF+images, duplicate names |
| 4 | Split PDF | ranges/extract/every-N; invalid ranges caught |
| 5 | Images→PDF | reorder, A4/Letter/fit, EXIF orientation |
| 6 | PDF→Images | page range, DPI presets, size warning |
| 7 | Compress Images | batch, slider, before/after, EXIF/GPS strip |
| 8 | Convert Image | JPG/PNG/WebP (+HEIC read), transparency bg |
| 9 | ZIP create + extract | UTF-8 names, zip-slip + zip-bomb guards |
| 10 | Files & history | outputs list, re-open/share, auto-purge |
| 11 | Document Scanner | camera → edge-detect/deskew → PDF (needs physical phone) |
| 12 | OCR | searchable PDF + text (bundled models) |
| 13 | Signature & Stamp | draw, place, flatten |
| 14 | Vault | biometric + AES-GCM, auto-lock, export/import |
| 15 | Settings + Privacy dashboard | processed counter, crash-log viewer |
| 16 | Share-sheet | Android share-intent entry |
| 17 | Release prep | icon, splash, signing, store copy, `flutter build appbundle` |
| 18 | Hardening & QA | full edge-case matrix on device, network-egress check, release soak test |

## Release checklist (Phase 17)
Google Play developer account ($25 once) · signing keystore (`key.properties` outside git) · privacy policy page ("no data collected" — draft lives in docs) · store listing copy + screenshots · in-app privacy policy section · data-safety form: "No data collected/shared".

## Risks
- Bundled OCR models add ~10–20 MB APK size (price of the offline guarantee); size budget ≤ 60 MB download
- OCR requires Play Services on the device → graceful degradation elsewhere (Tesseract fallback is a phase-2 option)
- True HEIC *write* is best-effort; HEIC read + JPG/PNG/WebP output always work
- Emulator camera is poor — scanner feature needs a physical Android phone
- Exotic corrupt files can only be fully proven on real devices (feature 18)
