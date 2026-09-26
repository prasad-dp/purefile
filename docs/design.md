# PureFile — Design System

## Brand personality
Calm, trustworthy, private. The UI feels like a tool, not a social app: fast screens, clear feedback, honest messages. Folder + shield mark with a teal gradient carries the brand.

## Color palette (Material 3, seeded from Pure Teal)

### Brand
| Token | Light | Dark |
|---|---|---|
| primary | #0F766E teal | #5EEAD4 |
| onPrimary | #FFFFFF | #042F2E |
| primaryContainer | #CCFBF1 | #134E4A |
| onPrimaryContainer | #042F2E | #CCFBF1 |
| brand gradient (icon, headers, hero) | #0F766E → #0284C7 (teal→sky) | same |

### Tool category colors (home grid icon chips)
| Category | Color |
|---|---|
| PDF tools | #E11D48 |
| Image tools | #7C3AED |
| ZIP tools | #D97706 |
| Scan | #059669 |
| OCR | #2563EB |
| Sign | #DB2777 |
| Vault | #475569 |

### Semantic
success #16A34A · warning #F59E0B · error #DC2626 · info #0284C7

### Neutrals
| Token | Light | Dark |
|---|---|---|
| background | #F6F8F8 | #0B1210 |
| surface | #FFFFFF | #111A18 |
| surfaceVariant | #EEF2F2 | #18231F |
| text primary | #0F172A | #E2E8F0 |
| text secondary | #475569 | #94A3B8 |
| outline | #E2E8F0 | #24312D |

All text/surface pairs must pass WCAG AA (4.5:1 body, 3:1 large).

## Typography
- System fonts only (Roboto / SF Pro) — zero APK cost, platform-native feel.
- Titles w600 · body w400 · captions w500 secondary color.
- File sizes/percentages use tabular figures (FontFeature.tabularFigures).
- Scale: display 32 · title 22 · section 16 w600 · body 14–15 · caption 12.

## Shape & spacing
- Cards 16 px radius · chips 12 px · pill buttons · sheets 24 px top radius.
- Base grid 4 px; screen padding 16; grid gaps 12.
- Tonal surfaces + subtle borders; minimal elevation (0–2).

## Iconography
- Material Symbols Rounded for UI icons.
- App icon: rounded square, teal→sky gradient, folder + shield mark (flutter_launcher_icons placeholder until final art).
- Tool card icon: 44 px rounded-square chip, category color at 12% opacity fill, icon in full category color.

## Screens (spec)
1. Onboarding (first launch, skippable): what PureFile does → "Your files never leave your phone" → done.
2. Home: search bar, category-sectioned tool grid (2 cols phone / 4 cols tablet), privacy badge ("0 uploaded · works offline"), recent outputs strip.
3. Tool flow (shared): Pick (file/gallery/camera + formats hint) → Options (per-tool, size badges, combined size) → Progress (determinate bar, %, cancel) → Result (% saved hero, share / save to gallery / open, "Process another").
4. Files & history: chronological outputs, size, tool chip, share/delete/re-open.
5. Scanner: camera preview → auto-capture on edge detect → crop/deskew editor → add pages → Save PDF.
6. OCR: pick/scan → language chips → progress with per-page preview → result (searchable PDF + text tab, copy).
7. Signature: drawing canvas → saved signatures row → place on page thumbnails (pinch/position) → flatten.
8. Vault: lock screen (biometric + PIN fallback) → encrypted browser → auto-lock setting.
9. Settings: theme, default quality, auto-purge, secure delete, language, Privacy dashboard (processed count, 0 uploaded, permissions), crash-log viewer.
10. Error/empty states: designed empty state per screen; typed error cards with a "what to do" line.

## Accessibility
- TalkBack/VoiceOver labels on every interactive element.
- Survives 200% font scaling (maxLines + overflow deliberate, no fixed heights).
- Touch targets ≥ 48 dp; progress always cancellable.

## Responsiveness & motion
- Phones portrait/landscape, tablets, foldables; two-pane tool flow on wide screens.
- Motion 150–250 ms easeOutCubic; no decorative loops while a job runs.
