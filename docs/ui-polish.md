# UI polish & size pass (F19 + F19b — post-plan optimization)

## 0. F19b — the iOS-craft pass (full-surface redesign)

The second polish layer re-authored every screen in the iOS design language
while staying Material 3 underneath (unified theming, no Cupertino/runtime
dependency):

- **Theme rebuilt**: systemGroupedBackground surfaces (`#F2F2F7` / true black
  dark with `#1C1C1E` cards), hairline separators (0.5px), SF-style type
  tracking (negative letter-spacing up the scale, weight-first hierarchy),
  20pt card radius with whisper shadows (light) / fill-based depth (dark),
  tinted focus rings on fields, crafted switches (green-on like UISwitch),
  no-splash ink (iOS has no material ripple), 17pt app-bar titles.
- **New widgets**: `ios_group.dart` — PfSection / PfGroupItem (chevron,
  destructive tint, hairline separators that skip first/last edges — the
  Settings grammar) + PfSectionHeader; `hero_header.dart` — gradient large
  title with white-tinted circular action buttons.
- **Home**: gradient hero header with 28pt large title, glassy iOS search
  capsule, refined category dots, floating cards.
- **Settings + Privacy dashboard**: full inset-grouped conversion — tinted
  32pt icon plates (iOS Settings style), stat pair on gradient plates with
  soft shadows, destructive reset as a quiet red row.
- **History**: grouped cards, tinted type plates, iOS share glyph, crafted
  circular empty state.
- **Vault setup/lock**: gradient lock plates with glow shadow replacing flat
  icons.
- **Onboarding**: layered hero plates (gradient → inner white-glow ring →
  icon), gradient page dots, height-1.5 body copy.
- **Tool flow pick stage**: gradient icon plate matching the card language;
  **file chips**: tinted doc plates + tabular size numerals.
- **Crash log**: severity-tinted plates (amber flutter / red platform),
  green shield empty state.
- All haptics/motion tokens from F19 retained; every screen scrolls as a
  floating group over the grouped background — one coherent, hand-crafted
  feel.

Gates after F19b: analyze 0 · 243/243 · release AAB rebuilt · egress green.

## 1. Application size — measured, then fixed

## 1. Application size — measured, then fixed

Baseline (release, fat APK): **95.3 MB** — dominated by the 5 bundled ML Kit
OCR models (~25 MB apiece for the largest scripts; that is the cost of the
"OCR works in airplane mode" promise and is non-negotiable).

| Build | Size | When to use |
| --- | --- | --- |
| `flutter build apk --release` | 95.3 MB | side-load / sharing one file |
| `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols` | **29.5 MB (arm32) / 35.7 MB (arm64)** | direct install — every modern phone gets arm64 |
| `flutter build appbundle --release` | 78.3 MB | Play Store — generates per-device downloads ≈ the split-ABI sizes |

**What each flag buys:**
- `--split-per-abi`: drops the other architectures' native libraries
  (−60%).
- `--obfuscate --split-debug-info=build/symbols`: Dart symbol stripping
  (smaller + reverse-engineering harder; keep `build/symbols` if you ever
  need to symbolicate a crash — alongside the in-app crash log).
- AAB: Play does the splitting for you; users download ~30–36 MB.

**Deliberate non-optimizations** (would break promises):
- Removing OCR model bundling → OCR would silently depend on Play Services
  downloads (violates the offline guarantee).
- Tree-shaking icons/fonts is already automatic; no hand-pruning needed.

## 2. UI/UX polish (F19 layer on the locked design language)

- **Motion tokens** (`PfMotion`): one curve family (`easeOutCubic`) and three
  durations (160/240/360 ms) so every screen moves identically. Unified page
  transitions: zoom on Android, Cupertino on iOS.
- **Haptics** (`PfHaptics`): light tick on tool-card taps, success pulse when
  a job completes. All wrapped — a missing platform channel never throws
  (tests/desktop stay silent).
- **Tool cards**: press-scale animation (springs back on release), icon chips
  gain a category-colored gradient + hairline ring — flatter tiles read more
  modern without leaving Material 3.
- **Privacy badge** is now the hero: brand teal→sky gradient with white text
  instead of a tinted container — the core promise gets the visual weight.
- **Theme depth**: warmer light surface (`#F4F7F6`), deeper teal-undertoned
  dark surface (`#0A100E`/`#101917`), tinted elevated dialogs (no gray
  boxes), borderless app bars with tuned title typography, 50px controls.
- **Dark-mode category colors**: chroma-lifted (`Color.lerp` toward white
  18%) so chips keep contrast without neon blowout.
- **About card** shows the real generated brand icon instead of a generic
  info glyph.

## 3. Everything inside purefile/

The `purefile/` folder is the complete, self-contained codebase + docs:
source (`lib/`, `tool/`), tests (`test/`), all documentation (`docs/` incl.
`README.md` at the root as the index), release artifacts recipes, and the
signing setup (gitignored). Nothing needed to build/ship lives outside it
beyond the Flutter SDK itself.

## 4. Verification

- `flutter analyze` — 0 issues
- `flutter test` — 243/243
- Release AAB + split-ABI APKs rebuilt after the polish (sizes table above)
- Egress check still passing (polish added zero networking)
