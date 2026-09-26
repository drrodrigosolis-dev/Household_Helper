# Sprint 16 — v1.1: Spanish

Owner decision 25 (`docs/PROGRESS.md`): every default accepted ("run Spanish").

## Decisions
1. **Variant:** neutral Latin-American Spanish, "tú".
2. **Scope:** every screen, alert, notification, widget and Shortcuts phrase (String Catalogs: `Localizable`,
   widget `Localizable`, `AppShortcuts`, `InfoPlist` for the Face ID prompt). User data is never translated. Seeded
   categories and the first account are named in the device's language when the data is first set up
   ("Supermercado", "Cuenta principal"); existing data keeps its names.
3. **Language choice:** follows the device (and iOS's per-app language setting); no in-app switch.
4. **Formats:** dates, numbers and currency follow the region, not the language.
5. **Quick Add:** understands Spanish words whatever the language: "hoy", "ayer", weekday names ("miércoles",
   "mié"), "ingreso"/"recibido"/"recibí" for income, "gasto" for an explicit expense. Like English, no future-date
   word.
6. **AI:** the on-device summary is asked to write in the app's language; if it can't, the deterministic summary shows.
7. **Walk:** every tab, Settings and Quick Add in Spanish, light and largest text (`SpanishWalkUITests`).

## How the catalog is kept
The catalogs were written from the source (no Xcode in the cloud session); keys with interpolations use Xcode's
format (`%@`, `%lld`, positional `%2$lld` where Spanish reorders). The local session verifies with
`xcodebuild -exportLocalizations` that every key the compiler extracts has a Spanish value (L-010); keys it reports
missing are added. `SpanishTests` checks each catalog is valid, complete and keeps every placeholder.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | String Catalogs (app 585 keys, widget 16, Shortcuts, Info.plist) | ☐ | ☐ |
| 2 | Spanish Quick Add words; Spanish seeds and first account for new data | ☐ | tests |
| 3 | Summary language; `CFBundleLocalizations` en, es | ☐ | ☐ (device) |
| 4 | Spanish walk UI test; export check on the Mac (L-010) | ☐ | ☐ |

## Close-out
☑ CI green (run 36268510203, `25afbec`) · ☑ Spanish walk reviewed (`docs/walk/sprint-16/`) · ☑ export check (L-010, `69d9801`, run 36270046170 green) · ☑ PROGRESS + PR

Walk finding (run 36268510203): the default task columns were seeded in English for Spanish users. They are now
seeded as "Por hacer / En curso / Hecho" (`TaskBoardService.spanishColumnNames`, tested in `SpanishTests`); existing
boards keep their names (stored data, renameable). Open, minor: "Sin movimientos" truncates at the largest text size.
