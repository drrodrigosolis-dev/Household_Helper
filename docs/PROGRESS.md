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
| 6 — Analytics | CI green | Sprint 5, run 36216543703 on `a41b742` (lint, build, unit, UI all green; walk in `docs/walk/sprint-9/run-36214979821`). Posted transactions, plus pending when Include pending is on (owner decision); charts carry audio-graph descriptors and tables. Data-safety reviews fixed. |
| 7 — Backup/export | CI green | Sprint 6, run 36216543703 on `a41b742`. Folder backup (DTO v1 + media), validated restore that merges by id in one save, CSV with formula guard. Data-safety reviews fixed (incl. restore keeping intact local photos and this device's lock setting). Google Sheets export dropped (owner decision). Files-app restore on a device queued (WALK-QUEUE). |
| 8 — Intelligence | CI green | Sprint 7, run 36216543703 on `a41b742`. On-device only, deterministic fallback everywhere; switches on by default where Apple Intelligence is available (owner decision). Suggestions never replace named or user-set values; a suggested description must use the note's own words; narrative figures are app-filled placeholders. UI tests run without the model; on-device checks queued (WALK-QUEUE). Receipt extraction and smart search: Mac backlog. |
| 9 — Optional system surfaces | CI green | Sprint 8, run 36216543703 on `a41b742`. Widget (small + medium) reads an app-written snapshot, sample figures under the free team (owner decision); Quick Add link; Shortcuts intents (parser-only log with confirmation, source Shortcut). Widget and Shortcuts on a device queued (WALK-QUEUE). |
| 10 — Hardening | in progress | Reviews done: privacy, accessibility, destructive actions, data safety, compile. Fixed and green in run 36216543703: Face ID gate + app-switcher cover; non-drag reordering; VoiceOver labels; dark-mode chart contrast; rollback guard on every service write; atomic category move-and-delete; link cleanup; restore keeping intact photos; privacy manifests; Sprint 9 v1 gaps (task↔transaction link, appearance, default Quick Add type, About). Walk-review fixes (large-text Analytics rows, About text) green in run 36216690421 on `1403711`. Awaiting CI: the review fixes for the owner-decision changes (`8f653f6`) and the task-link UI test; security-review fixes (`485d3ee`: backups validated before any photo is read, 500 MB total photo cap, restored photos re-encoded, photos written with complete file protection, Face ID on the Log Transaction shortcut, the lock never switches itself off); v1 audit gaps (wishlist↔task links both ways with the item listing its tasks, linked tasks in the transaction editor, Settings › Household for the starting balance/date and currency, Quick Add on the Current balance card, Recent activity rows open their own tab) plus UI tests for the flows the audit found untested. Reduce Motion: checked in code — the app has no custom animations or transitions (`withAnimation`, `.animation`, `.transition` unused), so only system animations run and they follow the setting. Remaining: device-only checks (WALK-QUEUE, MOVING-TO-MAC). |

Statuses: not started / in progress / CI green / blocked.

## Owner decisions (2026-09-26)
**SchemaV1 frozen: not yet** (freezes at the first install on the owner's device; update this line then).

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


## Defaults awaiting the owner's review (Phase 10)
- **Currency after records exist (§6.3):** Settings › Household refuses the change and says why, rather than §6.3's
  "warn, then confirm". v1 stores every amount in one currency, so a confirmed change could only relabel history
  (what §6.3 forbids) or convert it (out of scope); §6.3 step 5's "start a new data set" is what the screen suggests.
  Starting balance and date can be corrected any time, with a confirmation, since they are a baseline (§9.1).
- **Log Transaction shortcut with the lock on:** asks for Face ID/passcode first; whether a background shortcut can
  show that prompt needs a device (WALK-QUEUE). If it can't, the shortcut refuses with "Household Hub is locked".
- **Wishlist↔task link:** several tasks may link one item; the item's own back-link names the task that linked it
  last, and the item's detail lists every linking task.

## Remaining uncertainty (Phase 10 data-safety review)
- **Two writers of wishlist rows.** `TaskBoardService` sets and clears `WishlistItem.linkedTaskID` from its own
  context while `TransactionService` owns the rest of the item. A task saved at the same instant as its linked item
  is deleted could leave a dangling `linkedWishlistItemID` in the store; backups still export (dangling links are
  dropped before validation) and restores validate. How SwiftData merges concurrent saves to one object across
  contexts is unverified; a Mac-side stress test or routing link writes through one actor would close it.
- **File protection** (`.completeFileProtection` on photos) is ignored by the Simulator, so CI can't exercise it. If
  the phone locks during a long "Back up now", photos not yet read are left out and the user is told.
- **A total photo cap of 500 MB per restore:** past it, remaining photos count as missing and the data still
  restores (the review showed a hard refusal would make large legitimate backups unrestorable).
