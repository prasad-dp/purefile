# PureFile — Requirements (behavior contract)

Functional and non-functional requirements. Every requirement is testable; `edge-cases.md` defines the test fixtures.

## Functional requirements

### Shared tool pipeline (all tools)
- F1. User picks files via file picker, gallery, or camera (scanner).
- F2. Validation before any processing: file exists; size ≤ 50 MB per file; batch ≤ 30 files / 100 MB; extension matches magic bytes; PDF encrypted → password prompt; free storage ≥ ~2× input.
- F3. Oversized files rejected at pick time with friendly message + tip; remaining batch proceeds.
- F4. Every job runs in a background isolate with determinate progress and cancel; cancel removes temps, never leaves a partial history entry.
- F5. Result screen: output name/size, % saved (when compression applies), share, save to gallery (images), open.
- F6. Output names never overwrite (auto-numbered `name (2).ext`).
- F7. Originals never modified (read-only inputs) — verified by test.
- F8. Every failure shows a human message + suggested fix; typed errors, never raw stack traces.

### Tools
- F9. Compress PDF: Low/Medium/High; result ≤ original else keep original + "Already optimized — kept your original".
- F10. Merge PDF: 2+ PDFs and/or images, any order, reorderable, duplicate input names OK.
- F11. Split PDF: custom ranges (e.g. 1-3,5), extract selection, every-N; invalid ranges rejected with message.
- F12. Images→PDF: JPG/PNG/WebP/HEIC(read) → one PDF; A4/Letter/fit-page; reorder; EXIF orientation; transparent PNG flattened to white.
- F13. PDF→Images: JPG/PNG per page; page range; DPI 1×/2×/300; warn when output may exceed input.
- F14. Compress Images: batch; quality slider; before/after sizes per image + total; strips EXIF/GPS by default (toggle).
- F15. Convert Image: JPG↔PNG↔WebP; HEIC readable; transparency background color for JPG.
- F16. ZIP Create: arbitrary files → single ZIP; UTF-8 names (emoji/Cyrillic OK).
- F17. ZIP Extract: browse entries; extract all/selected; nested ZIPs; zip-slip + zip-bomb protection; AES-encrypted ZIP → typed unsupported.
- F18. Scanner: camera with auto edge-detect/deskew/shadow-clean; multi-page; save as PDF; no watermark.
- F19. OCR: scanned PDF/image → searchable PDF + copyable text; Latin/CJK/Devanagari/Arabic (bundled models); rotated text handled; blank page → "No text found".
- F20. Signature: draw (saved for reuse), place/resize on page thumbnails, flatten into PDF.
- F21. Vault: biometric + PIN fallback; AES-GCM at rest; auto-lock on background; secure delete; encrypted export/import; forgotten PIN = unrecoverable (stated at setup).
- F22. History/Files: outputs with tool, size, date; share/delete/re-open; auto-purge after N days (default 30, settable, off option).
- F23. Privacy dashboard: files-processed count, "0 uploaded", permission states, crash-log viewer.
- F24. Share-sheet (Android): share files into PureFile → tool chooser; same 50 MB guard.
- F25. Onboarding: 3 slides, first launch only, skippable.

## Non-functional requirements
- N1. Offline: fully functional in airplane mode; no INTERNET permission on Android; zero-egress check per tool.
- N2. Devices: Android 7.0+ (API 24); arm64-v8a + armeabi-v7a; low-memory mode for 1–2 GB RAM; tablets/foldables/landscape; no Play Services → all but OCR work.
- N3. Performance: cold start ≤ 400 ms to interactive; UI never blocked by jobs.
- N4. Stability: no unhandled crash paths; global error handlers log locally; app survives native job failure.
- N5. APK size: ≤ 60 MB download budget (ABI splits); measured each phase.
- N6. Battery: wakelock only during jobs; no idle loops.
- N7. Privacy: no analytics, no identifiers, no network calls; crash logs local-only, user-viewable, purged too.
- N8. A11y: TalkBack labels, 200% font scaling, ≥48 dp targets, WCAG AA contrast.
- N9. i18n: all strings in .arb; English at launch.
- N10. Data safety: originals untouched; outputs in user-visible folder; uninstall removes everything.

## Limits (single source: lib/core/constants.dart)
maxFileBytes = 50 MB · maxBatchFiles = 30 · maxBatchBytes = 100 MB · minFreeStorageFactor = 2.0 · historyPurgeDaysDefault = 30 · dpiPresets [1.0, 2.0, 3.0] · imageQualityDefault = 80.

## Acceptance = feature "done"
Unit + edge-case tests pass · flutter analyze 0 issues · flutter test green · flutter build apk --debug compiles · verified on device · progress.md updated.
