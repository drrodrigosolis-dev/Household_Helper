# Sprint 6 — Phase 7: Backup and export

Planned 2026-09-26 while the owner was away with full authorization; recommended defaults taken and listed below
for review. Binding: §26 (backup DTO v1 and rules), §7.12, §5.5 (media), §21 Phase 7, §18 data-sensitive checklist.

## Defaults taken (owner may overrule)
1. A backup is a **folder** named `Household Hub Backup <date>` holding `backup.json` (the §26 DTO) and `Media/…`
   (the image files listed in `mediaManifest`). A folder is the "bundle" §26.1 allows and needs no zip code (iOS has
   no public zip API and packages are not allowed). Saved and picked through the Files app.
2. JSON uses ISO 8601 dates, sorted keys, and integer minor units for money. Recurrence rules are embedded as JSON
   objects, not opaque data. Every entity carries every stored field.
3. **Restore replaces everything** (no merge in v1) and asks first, saying so (§26.1). The whole file is decoded and
   validated before anything is written: schema version, unique ids, every reference (categories, merchants,
   series, wishlist links, task columns, subtask tasks), readable enum values, one currency, valid rules. Any
   problem refuses the restore and changes nothing.
4. Missing media does not block a restore: images that are not in the folder are dropped from their items, and the
   result says how many. Existing data is never touched when validation fails.
5. CSV export covers transactions (date, type, status, amount, currency, category, merchant, notes), RFC 4180
   quoting, and text cells starting with `= + - @` are prefixed with `'` so spreadsheets don't run them as formulas.
6. **Google Sheets export is not built** in this sprint: it needs Google OAuth configuration and a network
   dependency, both on the owner's confirm-first list. Listed for the owner in WALK-QUEUE.

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | `BackupDTO` v1 for every model + media manifest | §26 | ☐ | tests |
| 2 | `BackupService.export`: consistent snapshot, DTO + media list | §26 | ☐ | tests |
| 3 | `BackupService.restore`: full validation, then replace-all in one save; media copy | §26.1 | ☐ | tests |
| 4 | CSV export of transactions with quoting and formula guard | §21 | ☐ | tests |
| 5 | Settings › Data: Back up, Restore (confirm), Export CSV | §24.2 | ☐ | ☐ |

## Close-out
☐ CI green on final head · ☐ walk screenshots saved to `docs/walk/sprint-6/` and reviewed · ☐ data-safety review
(round trip, atomic restore, secrets) · ☐ PROGRESS + PR · ☐ WALK-QUEUE (Google Sheets decision)
