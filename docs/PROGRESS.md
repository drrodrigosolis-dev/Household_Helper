# Household Hub v1 — progress

Gate: a phase is **CI green** only when `.github/workflows/verify.yml` concluded `success` on the `build/v1` commit
that completes it (CLAUDE.md, "Autonomous CI-driven operation"; spec §28). Mirrored in the `build/v1 → main` PR description.

| Phase (§21) | Status | Note |
|---|---|---|
| 0 — Environment | CI green | Run 36192377205 on `729351a`: Xcode 26.6 / Swift 6.3.3 / iPhone 17 Pro Max iOS 26.5, lint+build+1 unit+1 UI passed. §27's iPhone 16 Pro Max is absent from the runner (open question for Phase 10). |
| 1 — Skeleton | CI green | Run 36193820270 on `44681ee` (5 unit, 3 UI tests). `HouseholdHubCore` framework (no SwiftUI) with the §5.2 factory, SchemaV1 + migration plan, §24.1 tab shell with placeholder screens, String Catalog. Judgment call: SchemaV1 holds only a minimal `AppSettings` and stays mutable until first release; Phase 2 adds the §7 models to it. Not yet seen visually (Dark Mode, Dynamic Type): pending the sprint walk decision. |
| 2 — Domain foundation | CI green | Sprint 1. Run 36196665245 on `ddc4b64` (58 unit, 3 UI). Money, Currency, HouseholdCalendar, ledger models, recurrence engine, balance calculator, transaction/category services. A data-safety review blocked the gate on 6 findings, all fixed before green. Details: `docs/sprints/SPRINT-1.md`. |
| 3 — Core UX | CI green | Sprint 2, run 36205435799 on `9635f01`. Walked in light/dark/largest text (`docs/walk/`); dark capture and large-text layout fixed along the way. Judgment call: category management goes under More › Settings › Categories (no §24.2 screen for it). |
| 4 — Wishlist | CI green | Sprint 3, run 36205435799 on `9635f01`. Purchase conversion is one atomic save on the transaction service; data-safety review (1 blocking, 3 should-fix) fixed before green. Default taken: a purchase transaction cannot be cancelled or turned into income (delete it instead). |
| 5 — Tasks | CI green | Sprint 4, run 36205565139 on `1c11590` (the push-triggered run 36205561992 on the same commit failed one timing-dependent UI test, the long-press Move to; fixed in `c08fcd2` with a plain menu path; re-confirmed on the next green head). Kanban board with drag and non-drag moves, subtasks, columns (delete moves tasks first), Quick Add Task. Data-safety review (1 blocking: missing invariant tests; 3 should-fix) fixed before green. Default for review: the last column is the done column (`docs/sprints/SPRINT-4.md`). |
| 6 — Analytics | in progress | Sprint 5 (`docs/sprints/SPRINT-5.md`). Posted transactions only; charts carry audio-graph descriptors and tables. |
| 7 — Backup/export | not started | |
| 8 — Intelligence | not started | |
| 9 — Optional system surfaces | not started | |
| 10 — Hardening | not started | |

Statuses: not started / in progress / CI green / blocked.
