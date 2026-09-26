# PureFile — Store listing copy (F17)

All copy is factual to the shipped app. The privacy claims below are enforced
by the manifest: **no `android.permission.INTERNET`**, so the OS itself blocks
any network access.

---

## App name
PureFile — Offline File Toolbox

## Tagline (30 chars)
Your files never leave your phone.

## Short description (80 chars)
PDF, image & ZIP tools that run 100% on your device. No uploads. Ever.

## Full description

PureFile is a private, fully offline file toolbox. Compress, merge, split and
convert PDFs, batch-edit images, pack and unpack ZIPs, scan documents with
your camera, OCR text, sign PDFs, and keep sensitive files in an encrypted
vault — all without an account, without ads, and without internet access.

**Zero uploads, provably.** PureFile does not request the INTERNET permission.
Android blocks all network access at the OS level. Airplane mode is the full
feature set.

**Tools included**
- Compress PDF — smaller files, never worse than the original
- Merge PDF — combine PDFs and images in any order
- Split PDF — ranges, extract pages, every-N
- Images → PDF — JPG/PNG/WebP/HEIC to a single PDF
- PDF → Images — render pages as JPG or PNG
- Compress Images — batch, quality presets, optional downscale
- Convert Image — JPG ↔ PNG ↔ WebP
- Create ZIP / Extract ZIP — with zip-slip and zip-bomb protection
- Document Scanner — camera capture, edge detect, perspective fix, clean PDF
- OCR — searchable PDFs with bundled on-device models (Latin, CJK, Devanagari)
- Sign & Stamp — draw once, place anywhere, flattened into the page
- Private Vault — AES-256-GCM encryption, biometric unlock, auto-lock
- History — your last 7 days of outputs, stored only on this device

**Why private by design**
- No internet permission — uploads are impossible, not just promised
- No accounts, no analytics, no ads, no tracking SDKs
- Everything runs on-device, in airplane mode
- Vault files are AES-256-GCM encrypted; forgotten vault secret = data stays
  unreadable (by design — stated up front)

**Free and open by simplicity.** No subscriptions. No watermark.

## What's new (first release)
First public release: 12 tools, encrypted vault, document scanner, OCR with
bundled offline models, and a privacy dashboard that shows exactly what the
app stored — and that it uploaded nothing.

## Keywords
pdf compress, merge pdf, split pdf, image converter, zip, document scanner,
ocr, sign pdf, private vault, offline tools, file manager, privacy

## Privacy policy (short-form, no URL needed)
PureFile processes all files entirely on your device. It has no internet
permission and cannot transmit data. Files you create stay in the app's
outputs folder; history entries expire after 7 days and can be cleared at any
time; crash logs are stored locally and never sent anywhere automatically.

## Data safety form (Play Store)
- Does your app collect or share any of the required user data types? **No.**
- Is all of the user data your app collects encrypted in transit? **N/A — the
  app has no network access.**
- Do you provide a way for users to request that their data is deleted? **N/A
  — the app has no server-side data.** Users can delete everything from
  Settings → Privacy dashboard.

## Notes for the release engineer
- Version: keep `version` in pubspec.yaml in sync with the about string in
  `lib/l10n/app_en.arb` (`aboutBody`).
- Signing: `android/key.properties` + `android/app/pf-release.keystore` are
  gitignored. **Losing the keystore loses the ability to update the listing —
  back it up (password manager / secure offline copy).**
- Build: `flutter build appbundle --release` →
  `build/app/outputs/bundle/release/app-release.aab`.
- Checklist before tagging a release: see the hardening matrix (F18) in
  docs/plan.md.
