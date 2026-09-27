# PureFile — Tester Guide (manual QA, all features)

This document is for a **human tester** running PureFile on a real device.
It covers every shipped feature (plan features 0–18): the 12 tools, the
vault, history, the privacy dashboard, settings, share-sheet intake, and
onboarding — plus the edge cases the automated suite can't exercise on
hardware.

Companion documents:

- `docs/edge-cases.md` — the 51-case automated contract (this guide turns the
  device-relevant ones into hands-on scripts)
- `docs/hardening.md` — what is already **[T]**est-proven / **[B]**uild-proven;
  its §7 device-only rows are mirrored in §9 here
- `docs/ci.md` — where to get the APK and how to install it

---

## 1. Get the app onto the device

**Option A — CI artifact (no toolchain needed)**

1. Open the repo on GitHub → **Actions** → latest *Android APK* run.
2. Download `purefile-arm64-apk` (modern phones) or `purefile-arm32-apk`
   (older devices) / `purefile-universal-apk` (largest, works everywhere).
3. Unzip, copy the `.apk` to the phone, tap it, allow "install unknown apps"
   when prompted. CI builds are release builds signed with the debug key —
   fine for testing (see `docs/ci.md`).

**Option B — build locally**

```bash
export PATH="$HOME/dev/flutter/bin:$PATH"
cd purefile
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

**Test devices matrix (recommended)**

| Device | Why |
| --- | --- |
| Modern Android phone (Android 12+) | primary path: camera, biometrics, share sheet |
| Old/slow Android (Android 8–10) if available | minSdk 24 floor, HEIC/legacy quirks |
| iOS device if available | Keychain-backed vault, Cupertino transitions |
| Any second device with Files/Photos apps | share-sheet intake tests |

---

## 2. Golden rules (what "correct" means everywhere)

These five contracts hold for **every** tool. Violations are bugs, always.

1. **Never worse than input** — a compress that doesn't shrink keeps the
   original bytes and tells you so ("kept original" / 0 % saved).
2. **Originals sacred** — after any tool finishes, the picked input files are
   byte-identical (open one before/after and compare visually at minimum).
3. **No silent failures** — every rejection shows a typed, human-readable
   message with a fix hint. No frozen spinners, no blank errors.
4. **Cancel cleans** — cancelling mid-job removes temp files and writes no
   history entry.
5. **Atomic outputs** — a finished job's output is complete and openable;
   there is never a half-written output file.

**Hard limits to probe** (rejects must happen *at pick*, with numbers in the
message): one file > 50 MB · batch combined > 100 MB · more than 30 files.

**Airplane mode check (the core promise)**: put the device in airplane mode
and run a full tool pass (any 3 tools end-to-end + vault import/export).
Everything must work identically. There is no network code in the app — the
release build has no INTERNET permission, so the OS itself forbids it.

---

## 3. App shell (onboarding, home, navigation, theme)

| # | Script | Expected |
| --- | --- | --- |
| 3.1 | Fresh install → launch | Onboarding shows 3 slides; gradient dots animate; swipe works; final slide's button enters the app; never shown again on relaunch |
| 3.2 | Kill app → relaunch | No onboarding; lands on home |
| 3.3 | Home grid | 12 tool cards, grouped by category (PDF red / Images purple / ZIP amber / Scan green / OCR blue / Sign pink / Vault slate); press-scale feedback + haptic tick on tap |
| 3.4 | Home search | Type "pdf" → only PDF tools remain; clear restores all; gibberish shows an empty state |
| 3.5 | Privacy badge / hero | Gradient hero title, search field below; badge states the offline fact |
| 3.6 | Navigation transitions | Pushing a tool zooms in (iOS-style); back pops smoothly; no white flashes |
| 3.7 | Dark mode | System dark → surfaces go true-black, cards #1C1C1E, hairlines visible, category colors still readable (chroma-lifted); light/dark switch is seamless everywhere |
| 3.8 | Rotation mid-tool | Rotate during a running job → job continues, progress preserved |
| 3.9 | Background/foreground mid-job | App backgrounded during a job → return → job still running or finished correctly |
| 3.10 | Crash log sanity | Settings → Privacy → Crash log: normally empty; the screen states "local-only · never sent anywhere" |
| 3.11 | Theme toggle in hero | Tap the sun/moon button next to the title: one tap flips light ⇄ dark; in Auto the icon shows what's active (sun by day / moon at night) with a small dot badge; app re-themes instantly |
| 3.12 | Theme persistence | Set Dark, kill the app, relaunch: starts dark with NO light flash; set Light, relaunch: starts light; Auto follows the OS setting |
| 3.13 | Settings segmented control | Settings → Appearance: Auto/Light/Dark segmented control reflects the current mode; selecting re-themes instantly; both controls (hero + settings) always agree |
| 3.14 | Light-mode card separation | In LIGHT mode every card (home tools, settings groups, history rows, tool flow) floats on the gray background with a visible whisper shadow — no flat white-on-gray blending |
| 3.15 | Sign pad in dark mode | Sign & Stamp: the drawing canvas stays WHITE with a visible border in both modes (white background is intentional — export requires it); strokes clearly visible |
| 3.16 | Dark-mode sweep | Toggle through all screens (home, tools, vault, history, settings, privacy, crash log, onboarding): no white flashes, no invisible borders/text, hairlines visible on cards |

---

## 4. The 12 tools — feature test scripts

Pick files through the in-app picker each time. Every tool follows the same
flow: **pick → options → progress (cancellable) → result (open/share)**.

### 4.1 Compress PDF (`pdf_compress`)

| # | Script | Expected |
| --- | --- | --- |
| 4.1.1 | Normal PDF, quality Medium | Output opens fine, smaller than input, % saved shown on result |
| 4.1.2 | Same PDF, Low vs High | Low = smaller/uglier, High = larger/prettier; monotonic sizes |
| 4.1.3 | Already-optimized PDF | "Never worse" rule: original kept byte-for-byte, result says 0 % / kept original |
| 4.1.4 | Cancel mid-job | Progress stops, nothing on result, no history entry |
| 4.1.5 | Password-protected PDF | Password prompt appears before work; correct password → proceeds; wrong → retry prompt, file unharmed |

### 4.2 Merge PDF (`pdf_merge`)

| # | Script | Expected |
| --- | --- | --- |
| 4.2.1 | 2–3 PDFs, reorder by drag | Output pages in the shown order |
| 4.2.2 | Mix: 1 PDF + 2 images | Images become pages; transparency flattened onto white (no black/checker) |
| 4.2.3 | Wide/landscape page in the mix | That page stays landscape, no sideways rotation |
| 4.2.4 | Two inputs with the same name | Both kept, no confusion |
| 4.2.5 | One corrupt item in the batch | Partial success: good items merged, corrupt item named in a warning; all-corrupt → error, no output |

### 4.3 Split PDF (`pdf_split`)

| # | Script | Expected |
| --- | --- | --- |
| 4.3.1 | Every-N mode on a 10-page PDF (N=4) | Chunks of 4/4/2, correct page contents |
| 4.3.2 | Ranges `1-3,5` | One PDF (or zip) with exactly pages 1,2,3,5 |
| 4.3.3 | Extract mode, pick 2 pages | One PDF per selected page |
| 4.3.4 | Out-of-range like `1-999` on 10 pages | Clamped or typed rejection — never a broken output |
| 4.3.5 | 1-page PDF with every-N | Single output or a clear message, no crash |
| 4.3.6 | Multi-piece output | Delivered as a zip; extract and verify the pieces |

### 4.4 Images → PDF (`images_to_pdf`)

| # | Script | Expected |
| --- | --- | --- |
| 4.4.1 | 3 photos (JPG/PNG/WebP if possible), reorder | PDF pages in shown order |
| 4.4.2 | Phone photo taken in portrait | Page is upright (EXIF baked — sideways is a bug) |
| 4.4.3 | Fit = A4 vs Fit = image size | A4 centers with margins; image-size pages match pixel aspect |
| 4.4.4 | Transparent PNG | Flattened onto white, not black |
| 4.4.5 | One huge image (12,000 px) | Completes, no crash/out-of-memory |

### 4.5 PDF → Images (`pdf_to_images`)

| # | Script | Expected |
| --- | --- | --- |
| 4.5.1 | 3-page PDF, DPI 150, PNG | 3 images, readable when zoomed |
| 4.5.2 | DPI 72 vs 300 | Visible quality difference; 300 not exponentially slower |
| 4.5.3 | JPG format | White background (no alpha), opens in gallery |
| 4.5.4 | Pages field `2` only | Only page 2 rendered |
| 4.5.5 | Multi-page output | Delivered as zip; single page → one image file |
| 4.5.6 | Encrypted PDF | Typed message (platform can't prompt) — no crash |

### 4.6 Compress Images (`image_compress`)

| # | Script | Expected |
| --- | --- | --- |
| 4.6.1 | 3 JPEGs, preset High | Smaller files, visually near-identical |
| 4.6.2 | Enable downscale, 4000 px photo | Max side clamped to 2560, aspect preserved |
| 4.6.3 | Tiny PNG (under cap, lossless) | Never-worse rule: original bytes kept, flagged |
| 4.6.4 | Mixed batch incl. one corrupt file | Partial success, corrupt named; multi-output arrives as `compressed images.zip` |
| 4.6.5 | EXIF-rotated photo | Output upright |

### 4.7 Convert Image (`image_convert`)

| # | Script | Expected |
| --- | --- | --- |
| 4.7.1 | PNG → JPG | Output is a real JPEG; transparency flattened onto white |
| 4.7.2 | JPG → PNG | Output is a real PNG (magic bytes / opens correctly) |
| 4.7.3 | JPG → WebP, PNG → WebP | Real WebP output (RIFF/WEBP header) |
| 4.7.4 | Same format (JPG → JPG) | Copy-through: byte-identical, "already this format" info, not a silent re-encode |
| 4.7.5 | `.jpeg` named input | Output normalized to `.jpg` |

### 4.8 Create ZIP (`zip_create`)

| # | Script | Expected |
| --- | --- | --- |
| 4.8.1 | Mixed files (PDF + images + txt) | Zip opens in Files app, all entries present, UTF-8 names intact |
| 4.8.2 | Emoji/Cyrillic file names | Names preserved inside the archive |
| 4.8.3 | Two files with the same display name | Deduped `name (1).ext` |
| 4.8.4 | Any file type | No format restriction (zip accepts anything) |

### 4.9 Extract ZIP (`zip_extract`)

| # | Script | Expected |
| --- | --- | --- |
| 4.9.1 | Normal zip with folders | Extracts preserving folder structure; opens via result screen |
| 4.9.2 | **Zip-bomb test zip** (ask dev, or highly-compressible 10k× same file) | Rejected *before* extraction with a clear message, nothing written |
| 4.9.3 | **Zip-slip test zip** (entry path `../../evil.txt`) | Rejected with nothing written anywhere — not even innocent entries |
| 4.9.4 | AES/password-protected zip | Typed "password-protected ZIPs not supported" |
| 4.9.5 | Empty zip | Typed error, no empty folder left |
| 4.9.6 | Extract the same zip twice | Second output folder gets a unique name, no silent overwrite |
| 4.9.7 | Nested zip inside the zip | Extracts fine; the inner zip can be extracted in a second pass |

### 4.10 Document Scanner (`scan`) — needs a real camera

| # | Script | Expected |
| --- | --- | --- |
| 4.10.1 | Photograph a document on a desk | Auto-crop trims to the page, shadows lifted, paper white, ink dark |
| 4.10.2 | Photograph a dark/blurry scene | Detection degrades gracefully — full frame kept, never a crash |
| 4.10.3 | Multi-page: 3 shots, reorder, delete one | Thumbnails reorderable; final PDF has the kept pages in order |
| 4.10.4 | Save PDF | Clean PDF output recorded in history under Scanner |
| 4.10.5 | Import from gallery (no camera path) | Same pipeline runs on the picked image |
| 4.10.6 | Retake several pages | Numbering restarts, no stale pages from the previous session |

### 4.11 OCR Text (`ocr`) — models are bundled; test in airplane mode

| # | Script | Expected |
| --- | --- | --- |
| 4.11.1 | Clean printed English page | Recognized text appears; searchable PDF: select/copy text in a PDF viewer |
| 4.11.2 | Outputs | `stem ocr.pdf` + `stem ocr.txt` companion with per-page sections |
| 4.11.3 | CJK page (Chinese/Japanese/Korean) | Text recognized (bundled CJK models) |
| 4.11.4 | Devanagari (Hindi) page | Text recognized (bundled model) |
| 4.11.5 | Arabic page | Typed limitation surfaced (no Arabic model exists in ML Kit) — expectation set, not a silent failure |
| 4.11.6 | Blank/empty page | Result still produced with a "no text found" warning, not an error |
| 4.11.7 | Handwriting | Best-effort recognition with expectations set |
| 4.11.8 | Page selection field | Only selected pages processed; all-out-of-range → typed rejection, nothing written |
| 4.11.9 | Airplane mode OCR | Works identically — no Play Services download (models bundled in the APK) |

### 4.12 Sign & Stamp (`sign`)

| # | Script | Expected |
| --- | --- | --- |
| 4.12.1 | Draw signature, place bottom-right on page 1 | Stamp appears only on page 1; other pages untouched |
| 4.12.2 | Signature background | Transparent — no white box over the PDF content |
| 4.12.3 | Size slider extremes (5 % → 80 %) | Clamped correctly, aspect preserved |
| 4.12.4 | All 5 anchor positions | Stamp hugs the chosen corner/edge with margin |
| 4.12.5 | Flatten result | Open in another viewer: stamp cannot be selected/deleted (real content, not an annotation) |
| 4.12.6 | Import stamp image instead of drawing | Works the same |
| 4.12.7 | Undo/clear on the pad | Strokes removed correctly |
| 4.12.8 | Empty canvas | Save disabled until at least one stroke exists |
| 4.12.9 | Out-of-range page number | Typed rejection, nothing written |

---

## 5. Private Vault (`vault`) — security-sensitive, test thoroughly

The vault encrypts files with AES-256-GCM under a key wrapped by the user's
secret. Biometrics only gate the session. Filenames never appear on disk in
plaintext.

| # | Script | Expected |
| --- | --- | --- |
| 5.1 | First open | Setup screen: enter secret (min 8 chars) + confirm; mismatch blocked; weakness copy honest |
| 5.2 | Unlock with secret | Unlocks; file list empty state shows guidance |
| 5.3 | Import a small file | Import encrypts a copy, then secure-deletes the original — after import the original is GONE from its location and the vault lists the entry (this is the designed behavior) |
| 5.4 | Import > 100 MB | Typed rejection at pick — nothing imported |
| 5.5 | Export to outputs | File reappears under its original name; opens correctly; content byte-identical to what went in |
| 5.6 | Import → export round-trip on a photo | Pixel-identical image back out |
| 5.7 | Remove an entry (confirm dialog) | Blob secure-deleted; other entries untouched |
| 5.8 | Lock (manual button) | Hard lock: secret required to return |
| 5.9 | Background the app < 3 min → return | Still unlocked (session alive) |
| 5.10 | Background 3–10 min → return | Soft lock: biometric prompt to re-gate; "use secret instead" dialog available |
| 5.11 | Background > 10 min → return | Hard lock: secret required |
| 5.12 | Biometric unlock | Device fingerprint/face prompt appears and unlocks; cancel prompt → stays locked |
| 5.13 | No biometrics enrolled | Soft lock degrades to secret prompt — no unlock loop, no dead end |
| 5.14 | Kill app → relaunch | Always locked (hard); key never persists unlocked |
| 5.15 | Destroy vault (wrong secret) | Refused before anything is deleted |
| 5.16 | Destroy vault (correct secret) | Confirm dialog (destructive styling) → everything wiped, vault back to setup |
| 5.17 | Import emoji/CJK-named file, then export | Name preserved exactly through the round-trip |
| 5.18 | Forgot the secret | Unrecoverable **by design** — setup copy states it; verify the app doesn't pretend otherwise |

Airplane-mode pass: repeat 5.3–5.7 with airplane mode on — the vault is fully
local.

---

## 6. History (7-day local retention)

| # | Script | Expected |
| --- | --- | --- |
| 6.1 | Run 3 different tools | History lists newest-first with icon, name, tool title, size, smart date (today = time, yesterday, else date) |
| 6.2 | Tap an entry | File opens via the OS viewer |
| 6.3 | Per-row share | Share sheet offers the file (folder entries offer up to 20 files) |
| 6.4 | Swipe to dismiss | Record removed; the actual file stays on disk (verify in Files) |
| 6.5 | Clear all (confirm) | List empties; copy states files are kept; spot-check a file still opens from its output location |
| 6.6 | Cancel a job mid-way | NO history entry appears |
| 6.7 | Change device date +7 days, relaunch | Old records purged automatically (7-day retention) |
| 6.8 | Delete an output file outside the app | Orphan row disappears on next history load |

---

## 7. Privacy dashboard & settings

| # | Script | Expected |
| --- | --- | --- |
| 7.1 | Settings hub | Grouped iOS-style sections; About card shows the brand icon + version 1.0.0 |
| 7.2 | Privacy dashboard — counters | "Files processed" reflects tools you actually ran; vault imports counted separately |
| 7.3 | Top tools | Most-used 3 shown with real titles |
| 7.4 | "Why the 0 stays 0" facts | States: no internet permission, no accounts, no tracking |
| 7.5 | Outputs storage row | Byte count roughly matches device usage; Clear (confirm) deletes output files but NOT vault contents — verify a vault file survives |
| 7.6 | Reset counters (confirm) | Back to zero; next tool run counts from 1 |
| 7.7 | Crash log screen | Newest-first cards; share-out works; clear-all works |
| 7.8 | App info truth-check | Every privacy claim on the screens must match reality (offline proven by airplane-mode tests) |

---

## 8. Share-sheet intake (send files INTO PureFile)

From Files, Photos, Gmail, WhatsApp, etc.: **Share → PureFile**.

| # | Script | Expected |
| --- | --- | --- |
| 8.1 | Share 1 PDF | App opens on a chooser listing only tools that accept a PDF (all PDF tools + Create ZIP) — nothing that would reject it |
| 8.2 | Share 1 image | Chooser shows image tools only |
| 8.3 | Share 1 zip | Chooser shows the ZIP pair only |
| 8.4 | Share mixed PDF + image | Chooser shows Merge + Create ZIP (maxFiles-aware) |
| 8.5 | Share a video | Chooser explains "no tool fits these files" instead of silently dropping |
| 8.6 | Share text/URL | Same friendly no-tool state |
| 8.7 | Share file > 50 MB | Same size guard + message as the in-app picker |
| 8.8 | Pick a tool from the chooser | Flow screen opens with the file(s) pre-filled and validated |
| 8.9 | Dismiss the chooser | Share dropped cleanly (like other apps), no leftover state |
| 8.10 | Cold start via share (app closed) | Share intent works from a killed app |
| 8.11 | Warm share mid-tool | Sharing while a tool screen is open routes to the chooser without losing the running job |

---

## 9. Device-only checklist (mirrors `hardening.md` §7)

These cannot be automated — they are the reason this document exists:

- [ ] Camera capture → scan pipeline on real hardware (D1)
- [ ] ML Kit recognition quality on real photographed pages: Latin + CJK + Devanagari (D2)
- [ ] Biometric prompt + real backgrounding auto-lock at 3 / 10 min (D3)
- [ ] flutter_secure_storage backed by real Keystore (Android) / Keychain (iOS) (D4)
- [ ] Share-sheet: 1 file and multi-selection from Files/Photos (D5)
- [ ] Play Store pre-launch report against the AAB (D6 — release engineer)
- [ ] Install CI arm64 artifact on a clean device; first-launch onboarding (D7)
- [ ] Full airplane-mode pass (§2) (D8)

---

## 10. Edge-case quick table (condensed from `edge-cases.md`)

Feed these inputs anywhere they apply:

| Input | Expected everywhere |
| --- | --- |
| 0-byte file | Rejected: "corrupted" typed message |
| Random bytes renamed `.pdf` / `.png` | Rejected at pick (magic-byte check) |
| Header-valid truncated PDF | Rejected by the tool probe ("re-export the file" hint) |
| Password-protected PDF | Password prompt; wrong password retries safely |
| Folder passed where a file is expected | Filtered by picker; if reached, typed error |
| 50.1 MB file | Rejected at pick with numbers |
| Exactly 50 MB | Accepted |
| 10-file batch with one 60 MB | One rejected, nine proceed |
| Emoji/Cyrillic/spaces in names | Preserved in outputs and zip entries |
| Two inputs with identical names | Both kept, outputs auto-numbered |
| 1×1 px image | Processes fine |
| 12,000 px image | Downscaled/processed, no crash |
| Storage nearly full | Insufficient-storage message with numbers |
| App killed mid-job | Relaunch: no orphan temps in outputs, no partial history |
| Two jobs triggered back-to-back | Serialized; both complete |

---

## 11. Recording results

Copy this template per session:

```
PureFile QA session
Date:        YYYY-MM-DD
Build:       [CI artifact tag or local build SHA]
Device:      [model, OS version]
Tester:      [name]
Mode:        [normal / airplane]

| Case    | Result (PASS/FAIL/BLOCKED) | Notes |
| ------- | -------------------------- | ----- |
| 4.1.1   |                            |       |
| 5.10    |                            |       |
| 8.1     |                            |       |
| D1..D8  |                            |       |

Bugs found:
- [BUG-1] case 4.2.3 — landscape page rotated — steps: …, expected …, actual …
```

**Bug report minimum**: case number · steps to reproduce · expected vs actual
· device + OS · screenshot/screen-recording · the input file (if shareable).
