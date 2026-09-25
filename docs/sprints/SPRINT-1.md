# Sprint 1 — Phase 2: Domain foundation

Started 2026-09-25 (cloud session). Builds on Phase 1, CI green in run 36193820270 on `44681ee` (§28 gate).
Process: `.claude/skills/household-sprint`. Owner answered "run" (all defaults) on 2026-09-25.

## Ground rules
- No lanes: every item touches the shared core model/persistence files.
- Domain-only sprint: items are "walked" by their tests (no UI surface this phase).
- Money in `Int64` minor units, `Decimal` only at boundaries, never `Double` (§6). Dates through `HouseholdCalendar`.
- Pushed in three chunks so CI checks each while the next is written.

## Items
| # | Item (§21 Phase 2) | Spec | Chunk | Built (CI green) | Walked |
|---|---|---|---|---|---|
| 1 | Money: minor units, checked arithmetic, sum/average/percentage, Decimal boundary, formatting | §6 | A | ☑ `b4dcc9f` | tests |
| 2 | Currency: ISO 4217 validation, minor-unit digits | §6.2 | A | ☑ `b4dcc9f` | tests |
| 3 | HouseholdCalendar: day/week/month/year bounds, relative day, DST-safe | §10 | A | ☑ `b4dcc9f` | tests |
| 4 | Categories: model, kinds, ColorToken with contrast check, system seed, archive-not-delete | §7.3, §8.4 | B | ☐ | tests |
| 5 | Transactions: model with explicit type/status/source, validation | §7.2 | B | ☐ | tests |
| 6 | Recurrence engine: weekly/monthly(day)/monthly(nth weekday)/yearly, end-of-month, leap years, DST | §7.5–7.6, §9.4 | B | ☐ | tests |
| 7 | Balance calculations: current (posted), pending impact, 30-day projection | §9 | C | ☐ | tests |
| 8 | Transaction service: create, materialize a recurring occurrence exactly once, delete-occurrence options | §8.3, §9.4 | C | ☐ | tests |

## Decisions (recorded in docs/research as they are made)
- Transaction model is `TransactionRecord`: `Transaction` collides with SwiftUI's type in the app target
  (same reasoning as the spec's `TaskItem`).
- References are UUIDs as §7 lists them (`categoryID`, `merchantID`, `recurringSeriesID`), not SwiftData
  relationships; services enforce integrity. Keeps backup DTOs (§26) a direct mapping.
- Amounts are stored as positive magnitudes; `type` gives the sign.
- `TransactionRecord.scheduledOccurrence: Date?` (not in §7.2) identifies which recurring occurrence a record
  materializes, so projection never counts it twice and it cannot be materialized twice.
- Current balance counts posted transactions strictly **after** `startingBalanceDate` and at or before "now".
- Rounding for division (average) is banker's rounding.
- Categories are `CategoryRecord` (ObjectiveC exports `Category`). System category names are seeded in English as
  editable data; localizing seeded names is an open question for the localization pass.

## Close-out
☐ CI green on final head · ☐ data-safety review · ☐ PROGRESS + PR description · ☐ research log
