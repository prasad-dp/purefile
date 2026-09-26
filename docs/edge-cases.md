# PureFile — Edge-Case Matrix (QA contract)

Every case is a named test. Fixtures live in `test/fixtures/`. Global rules:

- **Never worse than input**: a compression that doesn't shrink keeps the original and says so.
- **Originals sacred**: after every tool, input files are byte-identical (automated check).
- **No silent failures**: typed error + human message + fix hint.
- **Cancel cleans**: temps removed, no partial history entry.
- **Atomic outputs**: temp + rename only.

## Matrix

| # | Category | Case | Expected behavior |
|---|---|---|---|
| 1 | Size | 50.1 MB PDF into Compress | rejected at pick, message + tip, not processed |
| 2 | Size | exactly 50 MB file | accepted |
| 3 | Size | batch of 10 where 1 is 60 MB | 1 rejected, 9 proceed |
| 4 | Size | batch total > 100 MB (all ≤ 50 MB each) | rejected at start with combined-size message |
| 5 | Corrupt | 0-byte file | CorruptedFile at validation |
| 6 | Corrupt | random bytes named .pdf | magic-bytes check rejects at pick |
| 7 | Corrupt | random bytes named .png | same |
| 8 | Corrupt | PDF truncated mid-xref | CorruptedFile + "re-export the file" hint |
| 9 | Corrupt | PNG with corrupt header | typed error, no crash |
| 10 | Corrupt | ZIP with missing entries | reject with typed error listing problem |
| 11 | Security | ZIP with ../../evil entry paths | zip-slip: sanitized, extracted inside outputs only, warning shown |
| 12 | Security | ZIP declaring decompressed size > cap | zip bomb: rejected before extraction |
| 13 | Security | AES-encrypted ZIP | UnsupportedFormat ("password-protected ZIPs not supported") |
| 14 | Security | PDF with OpenAction JS | not executed; document still processes |
| 15 | Wrong input | image into Merge-as-PDF | only via Images→PDF path; registry hides invalid pairs |
| 16 | Wrong input | PDF into Compress Images | rejected at pick with tool-suggestion |
| 17 | Wrong input | folder passed as file | filtered by picker; defensive typed error if reached |
| 18 | Wrong input | password-protected PDF (no pass) | PasswordRequired prompt before processing |
| 19 | Wrong input | wrong password entered | WrongPassword retry, no file damage |
| 20 | Degenerate | PDF with 0 pages | typed error "This PDF has no pages" |
| 21 | Degenerate | PDF with 1 page (split every-5) | single output or clear message |
| 22 | Degenerate | 1×1 px image | processed, output valid |
| 23 | Degenerate | 12000 px image | downscaled per preset, no OOM |
| 24 | Degenerate | transparent PNG → PDF | flattened onto white |
| 25 | Degenerate | blank scanned page → OCR | "No text found" result state |
| 26 | Stress | 500-page PDF compress/split | page-streamed, progress, completes |
| 27 | Stress | 100-image batch → PDF | sequential in low-RAM mode; completes |
| 28 | Stress | ~50 MB image compress | completes in isolate; UI responsive |
| 29 | Stress | ZIP with 500 files | completes; guards #11/#12 enforced |
| 30 | Stress | nested ZIP inside ZIP | inner archive offered for further extraction |
| 31 | Names | two inputs with identical names | both kept; outputs auto-numbered |
| 32 | Names | emoji/Cyrillic/spaces in names | preserved in outputs and ZIP entries (UTF-8) |
| 33 | Names | output name collision | auto-numbered name (2).ext |
| 34 | Env | storage nearly full | InsufficientStorage with numbers in message |
| 35 | Env | permission denied | typed error + "Open settings" action |
| 36 | Env | app killed mid-job | relaunch: orphan temps swept, no partial history |
| 37 | Env | two jobs triggered | serialized queue, both complete |
| 38 | Env | device rotated mid-job | job continues, UI state preserved |
| 39 | Env | HEIC input on Android < 8.1 | typed unsupported |
| 40 | Per-tool | image-heavy PDF compress (tiny ratio) | honest %; kept original if larger |
| 41 | Per-tool | EXIF-rotated photo | upright in PDF/compress/convert |
| 42 | Per-tool | rotated/handwritten OCR | rotated handled; handwritten best-effort + expectation |
| 43 | Per-tool | empty signature canvas | save disabled until stroke exists |
| 44 | Vault | wrong PIN ×N | exponential lockout backoff |
| 45 | Vault | biometric not enrolled | PIN fallback offered |
| 46 | Vault | vault file corrupted | typed integrity error, other entries unaffected |
| 47 | Share | share-sheet file > 50 MB | same size guard + message |
| 48 | Share | share-sheet with 0 valid files | friendly "nothing to process" |
| 49 | Unicode | OCR on CJK/Devanagari/Arabic | text extracted (bundled models) |
| 50 | Cancel | cancel mid-compress / mid-OCR | isolate stops, temps removed, no history entry |
| 51 | OCR | device without Play Services | OcrUnavailable; other tools unaffected |

## Fixtures (test/fixtures/)
empty.pdf · junk.pdf (random bytes) · junk.png · truncated.pdf · encrypted.pdf · one_page.pdf · 500_page.pdf (test-setup generated) · 1x1.png · big_12000px.jpg (generated) · transparent.png · exif_rotated.jpg · zipslip.zip · zipbomb.zip · aes_zip.zip · cjk/devanagari/arabic scan images · emoji/Cyrillic named files.
Where a fixture can't be committed (size), the test setup generates it deterministically at runtime.
