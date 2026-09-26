# Household Hub v1 — progress

Gate: a phase is **CI green** only when `.github/workflows/verify.yml` concluded `success` on the `build/v1` commit
that completes it (CLAUDE.md, "Autonomous CI-driven operation"; spec §28). Mirrored in the `build/v1 → main` PR description.

| Phase (§21) | Status | Note |
|---|---|---|
| 0 — Environment | CI green | Run 36192377205 on `729351a`: Xcode 26.6 / Swift 6.3.3 / iPhone 17 Pro Max iOS 26.5, lint+build+1 unit+1 UI passed. iPhone 17 Pro Max is the design/test reference (owner decision replacing §27's 16 Pro Max). |
| 1 — Skeleton | CI green | Run 36193820270 on `44681ee` (5 unit, 3 UI tests). `HouseholdHubCore` framework (no SwiftUI) with the §5.2 factory, SchemaV1 + migration plan, §24.1 tab shell with placeholder screens, String Catalog. Judgment call: SchemaV1 holds only a minimal `AppSettings` and stays mutable until first release; Phase 2 adds the §7 models to it. Not yet seen visually (Dark Mode, Dynamic Type): pending the sprint walk decision. |
| 2 — Domain foundation | CI green | Sprint 1. Run 36196665245 on `ddc4b64` (58 unit, 3 UI). Money, Currency, HouseholdCalendar, ledger models, recurrence engine, balance calculator, transaction/category services. A data-safety review blocked the gate on 6 findings, all fixed before green. Details: `docs/sprints/SPRINT-1.md`. |
| 3 — Core UX | CI green | Sprint 2, run 36205435799 on `9635f01`. Walked in light/dark/largest text (`docs/walk/`); dark capture and large-text layout fixed along the way. Judgment call: category management goes under More › Settings › Categories (no §24.2 screen for it). |
| 4 — Wishlist | CI green | Sprint 3, run 36205435799 on `9635f01`. Purchase conversion is one atomic save on the transaction service; data-safety review (1 blocking, 3 should-fix) fixed before green. Default taken: a purchase transaction cannot be cancelled or turned into income (delete it instead). |
| 5 — Tasks | CI green | Sprint 4, run 36205565139 on `1c11590` (the push-triggered run 36205561992 on the same commit failed one timing-dependent UI test, the long-press Move to; fixed in `c08fcd2` with a plain menu path; re-confirmed on the next green head). Kanban board with drag and non-drag moves, subtasks, columns (delete moves tasks first), Quick Add Task. Data-safety review (1 blocking: missing invariant tests; 3 should-fix) fixed before green. Default for review: the last column is the done column (`docs/sprints/SPRINT-4.md`). |
| 6 — Analytics | built, awaiting CI | Sprint 5 (`docs/sprints/SPRINT-5.md`). Posted transactions, plus pending when the owner turns on Include pending (owner decision); charts carry audio-graph descriptors and tables. Data-safety review fixed. Runs 36214979821/36214977752 on `e43e528`: build, 180 unit and 29 UI tests passed, lint red on one line fixed in `7dc2520`; a fully green run closes Phases 6–9. |
| 7 — Backup/export | built, awaiting CI | Sprint 6. Folder backup (DTO v1 + media), validated restore that merges by id in one save, CSV with formula guard. Data-safety reviews fixed (incl. restore keeping intact local photos and this device's lock setting). Google Sheets export dropped (owner decision). |
| 8 — Intelligence | built, awaiting CI | Sprint 7. On-device only, deterministic fallback everywhere; switches on by default where Apple Intelligence is available (owner decision). Suggestions never replace named or user-set values; a suggested description must use the note's own words; narrative figures are app-filled placeholders. Live model fixtures are opt-in (`TEST_RUNNER_HH_LIVE_AI=1`); UI tests run without the model. Receipt extraction and smart search: Mac backlog. |
| 9 — Optional system surfaces | built, awaiting CI | Sprint 8 (`docs/sprints/SPRINT-8.md`). Widget (small + medium) reads an app-written snapshot, sample figures under the free team (owner decision); Quick Add link; Shortcuts intents (parser-only log with confirmation, source Shortcut). Data-safety and compile reviews fixed. |
| 10 — Hardening | in progress | Reviews done: privacy, accessibility, destructive actions, Sprint 8 data safety and compile. Fixed: restore could delete an intact local photo (blocking); Face ID gate + app-switcher cover (v1 scope gap); non-drag reordering for subtasks and columns; VoiceOver chart/row/filter labels; dark-mode chart contrast; rollback guard on every service write; atomic category move-and-delete; link cleanup on delete; privacy manifests. Sprint 9 (`docs/sprints/SPRINT-9.md`) closes the remaining v1 gaps: task↔transaction link, appearance, default Quick Add type, About. Tests added: on-disk reopen through the migration plan, balance performance, launch metric, post-restore writes. |

Statuses: not started / in progress / CI green / blocked.

## Owner decisions (2026-09-26)
1. **Widget on a free-team device shows the sample figures** (spec §5.2/§24.4 as written), not an amount-free
   placeholder. Advisor's note on record: on a real phone those figures can be mistaken for the real balance.
2. **SchemaV1 freezes at the first install on the owner's device.** Until then fields may still be added to it
   directly; from that install on, every model change is a new `VersionedSchema` with a migration stage.
3. **Google Sheets export is dropped from v1.** CSV export covers spreadsheets; no OAuth, no network.
4. **iPhone 17 Pro Max is the v1 design and test reference** (same 6.9" class as the spec's 16 Pro Max, which the CI
   runner doesn't offer).
5. **Stay on the free Personal Team for v1.** App Groups, TestFlight, and CloudKit stay deferred; the widget keeps
   its fixture path.
6. **Analytics can include pending** (overrides Sprint 5 default 2): an Include pending switch on Analytics, off by
   default; pending items dated up to now then count, cancelled and future never do.
7. **AI switches on by default where Apple Intelligence is available** (overrides Sprint 7 default 1); each can be
   turned off. UI tests always run without the model.
8. **The model may suggest a description** (overrides Sprint 7's "no model description"): only one short line, no
   digits, sharing a word with what was typed, and only while the notes field still holds the parser's own text.
9. **Receipt extraction and smart search are built after the move to the Mac** (Sprint 7 default 5 confirmed; on
   the Mac backlog in `docs/MOVING-TO-MAC.md`).
10. **Shortcut entries get their own source** (`TransactionSource.shortcut`, overrides Sprint 8's `.widget`).
11. **Accent color: any color** via a color picker (overrides Sprint 9 default 3), with a warning when it would be
    hard to see in Light or Dark Mode; the palette stays as quick choices.

