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
| 4 | Categories: model, kinds, ColorToken with contrast check, system seed, archive-not-delete | §7.3, §8.4 | B | ☑ `ddc4b64` | tests |
| 5 | Transactions: model with explicit type/status/source, validation | §7.2 | B | ☑ `ddc4b64` | tests |
| 6 | Recurrence engine: weekly/monthly(day)/monthly(nth weekday)/yearly, end-of-month, leap years, DST | §7.5–7.6, §9.4 | B | ☑ `ddc4b64` | tests |
| 7 | Balance calculations: current (posted), pending impact, 30-day projection | §9 | C | ☑ `ddc4b64` | tests |
| 8 | Transaction service: create, materialize a recurring occurrence exactly once, delete-occurrence options | §8.3, §9.4 | C | ☑ `ddc4b64` | tests |

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

## Data-safety review (subagent, 2026-09-25) — gate BLOCKED, then fixed
| Finding | Fix |
|---|---|
| Failed `save()` left edits in the actor context for a later save to persist | `commit()` rolls back on failure in both services |
| Two service instances could each pass the "not materialized" check | One instance per container (`make(container:)` caches under a `Mutex`) + concurrency test |
| Deleting a recurring occurrence resurrected it in the projection | Occurrences are kept as `cancelled` markers; ordinary transactions are still deleted |
| Unknown stored enum/time-zone values silently became `.expense`/`.current` | Accounting reads (`ledgerLine()`, `series()`) throw `unreadableRecord` |
| Series inputs unvalidated; `reassign` skipped series kinds | `createSeries` validates; `reassign` checks series too |
| Duplicate settings / future starting balance | Sorted singleton fetch; `startingBalanceInFuture` |
| Stored formats only round-trip tested | Fixed-JSON fixtures for `RecurrenceRule` and `ColorToken` |

Not covered by a test: the rollback path itself (SwiftData offers no clean way to force `save()` to fail); verified by
reading. Residual, documented in `CategoryService`: `delete` in one actor vs `create` in the other can race.

## Close-out
☑ CI green on final head (run 36196665245, `ddc4b64`: 58 unit + 3 UI tests) · ☑ data-safety review (blocked, fixed) ·
☑ PROGRESS + PR description · ☑ research log. Walk: domain-only sprint, walked by its tests. **Sprint closed.**
