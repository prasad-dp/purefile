# PureFile — Architecture

## Layers (top → bottom)

```
UI — Flutter Material 3 (features/* screens + widgets/, error/empty states)
State — Riverpod; job state machine: idle → picked → validated → running → done|error|cancelled
Domain services — pure Dart, run in ISOLATES: pdf/image/zip/ocr/scan/sign/vault services
  every job: progress stream + cancel flag + timeout guard
core/ — constants (50 MB, batch caps) · validation (pre-flight) · file_io (atomic writes,
  safe unique names, temp cleanup, secure delete) · formats registry · errors (typed) ·
  isolate_runner · jobs (history, auto-purge, crash recovery, processed counter)
Storage — app-docs/outputs/ (results) · vault/ (encrypted) · shared_preferences · local JSON history
```

## Folder structure

```
purefile/
├── lib/
│   ├── main.dart                 entry + global error handlers
│   ├── app.dart                  MaterialApp, theme, router
│   ├── core/
│   │   ├── constants.dart        single source: 50 MB, batch caps, DPIs
│   │   ├── errors.dart           typed errors
│   │   ├── isolate_runner.dart   run(fn) → progress stream, cancel(), timeout
│   │   ├── file_io.dart          atomic writes, unique names, temp cleanup
│   │   ├── formats.dart          supported in/out formats per tool
│   │   ├── validation/           size, magic bytes, encryption, storage checks
│   │   ├── jobs/                 history, auto-purge, crash recovery
│   │   └── theme/                Material 3 light/dark from locked palette
│   ├── features/
│   │   ├── onboarding/           3 slides, first launch only
│   │   ├── home/                 searchable tool grid + privacy badge
│   │   ├── tools/                shared pipeline: pick → validate → options → progress → result
│   │   ├── pdf/                  compress/ merge/ split/ images_to_pdf/ pdf_to_images/
│   │   ├── image/                compress/ convert/
│   │   ├── zip/                  create/ extract/
│   │   ├── scan/  ocr/  sign/  vault/
│   │   ├── files/                outputs & history
│   │   └── settings/             privacy dashboard + crash-log viewer
│   ├── l10n/                     .arb files (localization-ready)
│   └── widgets/                  tool card, file chips, progress sheet
├── android/  ios/                thin platform shells
├── test/
│   ├── fixtures/                 real + deliberately broken samples
│   └── unit/  widget/            one suite per tool
├── docs/                         this documentation set
└── pubspec.yaml
```

## Offline guarantee (mechanics, not marketing)
1. Android build declares **no INTERNET permission** → OS-level proof nothing can upload.
2. ML Kit OCR uses **bundled models** (text-recognition bundled variants, not Play-Services-downloaded ones).
3. All plugins local-first; verified list in pubspec (no firebase, no http).
4. QA runs a zero-network-egress check per tool.
5. Phase-2 ads/Pro must live in one isolated module; a "pure offline" flavor excludes it.

## Reliability rules (enforced by architecture)
- **Originals are sacred**: inputs read-only; outputs only to outputs/. Tested: inputs byte-identical after every tool.
- **Isolate isolation**: every conversion in its own isolate with timeout — a native crash/hang can never freeze the app.
- **Atomic writes**: temp file + rename; a kill mid-write never leaves a corrupt "result".
- **Pre-flight validation** on every job: size ≤ 50 MB, exists, magic bytes vs extension, PDF-encrypted detection, free space ~2× input.
- **"Never worse than input"**: compression result ≥ original → keep original + say so.
- **Cleanup**: temps removed on finish, cancel, app start (orphan sweep). Vault delete overwrites bytes before unlink.
- **No silent failures**: typed error → human message + suggested fix.

## Concurrency & memory
- Page-by-page streaming for large PDFs; sequential low-memory mode on ≤2 GB RAM devices.
- Jobs queue sequentially (v1 documented behavior). Wakelock only during jobs.

## Packages (locked for MVP)
syncfusion_flutter_pdf (merge/split/compress; free community license <$1M revenue) · pdfx (render/preview) · flutter_image_compress (native compress/convert, HEIC read) · image (pure-Dart fallback) · archive (zip) · file_picker · share_plus · gal (save to gallery) · path_provider · google_mlkit_text_recognition (bundled) · camera · local_auth · encrypt (AES-GCM) · flutter_secure_storage · flutter_riverpod · go_router · shared_preferences · dev: flutter_launcher_icons, flutter_native_splash.

## Platform notes
- Android: minSdk 24, arm64-v8a + armeabi-v7a splits, scoped storage via SAF/MediaStore, share-sheet via intent filters, NO INTERNET permission.
- iOS (build-ready, release later): iOS 15+; branches only for HEIC write, Photos save, share targets.
- Devices without Play Services: all tools work except OCR → typed OcrUnavailable.
