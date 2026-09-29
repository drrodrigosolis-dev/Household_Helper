# Sprint 23 — v1.1: fixes from the local full audit (CI green; owner walk pending)

Input: `docs/audit/2026-09-28/FINDINGS.md` (local, audited `338a877`, 23 findings). Owner prompt 2026-09-28: every
finding gets an outcome; verify against the code first; data/money first; a test per fixed bug; one owner-questions
message with defaults; local re-verifies by finding ID.

## Ground rules
- SchemaV1–V3 are frozen (FrozenSchemaTests); F4's split adds SchemaV4 (`TransactionRecord.splitGroupID`).
- Data-sensitive fixes (A-001, A-003) pass household-data-safety-review.
- Local re-verifies in batches (one L-item per round), answering closed / reopened / not verified per ID.

## Outcomes
| ID | Sev | Outcome | Notes | Built (CI) | Verified (local) |
|---|---|---|---|---|---|
| A-001 | blocker | **fix** | Root cause: candidates are rebuilt from the start's whole seconds, so a start carrying fractions of a second (every "now") dropped its first occurrence. Engine compares against the whole-second start; test per rule. Also: the editor's Starts defaults to start of today and lists the next dates (A-020). | ☑ | ☑ L-023 (closed; default start only) |
| A-002 | medium | fix | Recent activity drops purchased wishlist items (their expense row stands for them). | ☑ | ☑ L-023 |
| A-003 | medium | fix (owner: default) | Import maps Description → Merchant for new imports; existing rows untouched. | ☑ | ☑ L-023 |
| A-004 | medium | fix | Shared keyboard Done button + interactive dismiss on every form with a number pad. | ☑ | ☑ L-023 (Done button; drag-down dismiss not verified) |
| A-005 | medium | fix | Debounced search, filtering off the per-keystroke path; measured by a UI performance test. | ☑ | ☑ L-023 |
| A-006 | medium | fix (owner: default) | Import suggests a category from merchant memory (the category the same merchant last had), shown in the preview; plus an "Uncategorized" filter. No new AI. | ☑ | ☑ L-023 (suggestion); Uncategorized filter by `Sprint23ListUITests` screenshot |
| A-007 | medium | fix (owner: default) | Multi-select in Transactions: Set category / Delete (confirmed). | ☑ | ☑ L-023 (delete); Set category by `Sprint23ListUITests` screenshot |
| A-008 | medium | not a bug (pending finger) | RefundUITests opens Refund… on a wishlist purchase with a real synthesized tap and passes on CI; likely the tap tool (the audit's own caveat). Local to confirm with a long press. | — | ☑ L-023: works by hand; the audit tap tool landed ~40 pt low (not a bug, status kept) |
| A-009 | medium | not a bug (pending finger) | BudgetsUITests taps `budgets.addEmpty` and passes; same caveat. | — | ☑ L-023: works by hand; same tap-tool offset (not a bug, status kept) |
| A-010 | low | not a bug (local to re-check) | The sheet already shows "Paid from" when there is more than one active account (`wishlist.purchase.account`); the walk's fresh install had one. | — | ☑ L-023 (two accounts show "Paid from"; not a bug, status kept) |
| A-011 | low | won't fix | iOS's own tab re-tap scrolls to top; there is no public API to re-expand a collapsed large title or show a hidden search field. A pull-down shows both (standard iOS). | — | — won't fix, acknowledged in L-023 |
| A-012 | low | fix (local to verify) | More uses a path the router clears on re-tap. Needs a check that iOS 26 reports the re-tap to the selection binding. | ☑ | ☑ L-023 |
| A-013 | low | fix (owner: default) | Hide the floating + on Recurring and Budgets (their toolbar + stays). | ☑ | ☑ L-023; Goals + fixed in 10ef984 |
| A-014 | low | fix | Hide the floating + while searching; bottom inset already on lists (re-check Budget). | ☑ | ☑ L-023; `Sprint23ListUITests` screenshot |
| A-015 | low | fix | Transaction editor Save disabled until something changes. | ☑ | ☑ L-023; `Sprint23ListUITests` |
| A-016 | low | fix | "Recorded in Budget" opens the expense. | ☑ | ☑ L-023 |
| A-017 | low | **feature, this sprint (owner)** | Budgets: previous months with spent/limit and rollover. | ☑ | ☑ L-024; `Sprint23AnalyticsUITests` screenshot |
| A-018 | low | **feature, this sprint (owner)** | Analytics: tap a slice/bar to see its transactions; change vs last month. | ☑ | ☑ L-024; `Sprint23AnalyticsUITests` screenshot |
| A-019 | low | fix | Wishlist empty state gets "Add item" (`wishlist.addEmpty`); Recurring already had one (`recurring.addEmpty`). | ☑ | ☑ L-023 |
| A-020 | low | fix | Recurring editor lists the next three dates; Starts defaults to the start of today. | ☑ | ☑ L-023 (editor lists the next dates) |
| A-021 | low | fix (owner: default, row renamed "Data") | §24 names the screen "Data"; make the row match. | ☑ | ☑ L-023 |
| A-022 | low | fix | Account delete checks use first, then confirms. | ☑ | ☑ L-023 |
| A-023 | low | needs finger | Carried from L-018; WALK-QUEUE. | — | ☐ needs the owner's finger (status kept; WALK-QUEUE) |

## Features added by the owner (2026-09-28: "all this sprint")
| # | Feature | Plan | Built (CI) | Verified |
|---|---|---|---|---|
| F1 | Categories learned from manual edits, applied to imports and Quick Add | `Merchant.defaultCategoryID` (exists, never set until now); import lane | ☑ | ☑ L-024 |
| F2 | Recurring detection from history | Core finds merchant+amount repeating weekly/monthly; Recurring shows "Make it a bill?" suggestions | ☑ | ☑ L-024; detector noise fixed in 2bc8657 |
| F3 | Undo for delete and bulk edits | Undo banner; restores the same records (same ids, links) | ☑ | ☑ L-024 (single delete) and `Sprint23UndoUITests` screenshot; bulk delete → Undo by hand: L-034 walk pending |
| F4 | Duplicate and split transactions | Duplicate: no schema. Split: **SchemaV4** (optional `splitGroupID` on TransactionRecord), parts sum to the original. **Written (split lane)**: backup v5; editing a part's status/date/account/merchant moves every part, its type is fixed; deleting to one part unsplits it | ☑ | ☑ L-024; `Sprint23SplitUITests` screenshots (Mac full suite passes since f36b82e) |
| F5 | Month-end summary | Analytics section: last month spent vs budgets, top categories, goals | ☑ | ☑ L-024; `Sprint23AnalyticsUITests` screenshots |
| F6 | Search filters + saved searches | Amount range, date range, account; saved searches in device settings (not SwiftData) | ☑ | ☑ L-024; `Sprint23UndoUITests` screenshots |
| F7 | Budget alerts at 80 % / 100 % | Local notifications (names only), reusing the reminders plumbing | ☑ | ☐ planner walked by `BudgetAlertPlannerTests`, switch by `Sprint23RecurringUITests` screenshot; the notification itself: L-034 walk pending |
| F8 | Import presets per bank | Column mapping/date format/sign remembered per preset, in device settings | ☑ | ☑ L-024; `CSVImportPresetTests` |

Waves: wave 1 = the fixes (lanes: import A-003/A-006/F1; list A-005/A-007/A-013/A-014/A-015 + Uncategorized filter; lead:
the small ones). Wave 2 = features, after wave 1 is merged and pushed.

## Data-safety review (wave 1 + analytics, recurring, presets; 2026-09-28)
No loss of financial history, no double posting, no money writes in F2/F7, import still all-or-nothing.
- B1 (A-001 tests): monthly-on-weekday case added; end-to-end service test (due today, in Upcoming, posts once).
- B2 (bulk delete must offer "Delete and disable their series", §8.3): assigned to the undo lane (owns the list).
- B3 (deletionBlocker parity): `.inUse` and `.isDefault` asserted next to deleteAccount's refusals.
- S1 update keeps the record's merchant for the same name; S2 doc comment; S3 doc says "pre-selected"; S4 overflow
  test. Open, not blocking: S5 months before a budget's start show its current limit (product call); S6 a category
  that fell to zero isn't listed as "down"; S7 an occurrence earlier today is in Upcoming but not the projection
  until posted (pre-existing); S8 import mid-way merchant failure has no test.
- The split lane (SchemaV4) and the undo lane get their own review.

## Walk defects (local hand checks L-023/L-024, 2026-09-28) — fixed on the spot
Every audit fix but A-023 (needs the owner's finger) and every feature but F7 (not checked yet) was seen working.
The walk found these; lanes `lane-s23-polish-list` and `lane-s23-polish-edit`:
- ☑ Undo banner: longer timeout; the floating + no longer covers Undo (3b61cb5).
- ☑ Active date/amount filters show as chips; the menu no longer ticks "All time" for a custom range; Clear All Filters
  (693aa49, ff10eed).
- ☑ Refund rows are named after what they refund, not "Transaction" (af4c1e5, d34a0e8).
- ☑ Quick Add stores the description as the Merchant, as import does (F1 consistency) (05b5155, 6f37840).
- ☑ Split prefills part 1; Duplicate opens the copy; the keyboard Done no longer covers the field above it (c00fcb3,
  b68b7b2, 781d77c, 1e16a1e, 38fe95f).
- ☑ Analytics: Expenses labelled net of refunds (b4cc94a).
- ☑ Recurring detector groups by merchant and amount, so extra one-off charges don't hide a subscription (2bc8657).
- ☑ Wishlist › Goals: no floating + next to its own + (10ef984).
- ☑ The Spanish catalog test reads plural forms (it failed every plural entry); "movimiento" wording (10ef984).
- Kept: the delete confirmation before the Undo banner stays (the banner times out; financial history is never
  deleted on one tap).
- Closed: `TasksUITests` spring-load failed on the Mac (In Progress ended 200 pt past the edge; L-025 to L-032). Root
  cause and fix in Sprint 26's post-sprint notes (1f51430); the Mac's L-033 saw it fixed, 88/88.

## Owner decisions
- 2026-09-28: the phone holds no real data yet, so installing a build with SchemaV4 needs no backup first. SchemaV4
  still gets its migration tests and household-data-safety-review, and is installed only once CI is green; after
  that install it is frozen like V1–V3.

## Close-out (2026-09-29)
☑ CI green: run 36599247241 on `dba6f9e` (lint, build, unit, UI 88/88), which holds every Sprint 23 fix and feature;
the Mac's full UI suite on the same code is 88/88 too (L-033). ☑ data-safety reviews (wave 1; split and undo lanes).
☑ PROGRESS row · ☑ PR #2 body.

- **Shipped:** the 18 audit rows with a fix or feature outcome (A-001 to A-022 less A-008/A-009/A-010, not bugs,
  and A-011, won't fix) and features F1–F8, with SchemaV4 (`splitGroupID`), installed with `f183138` and pinned by
  `FrozenSchemaTests` since `2a9cb79`.
- **Walked:** every fixed ID and F1–F6, F8 by the Mac's hand checks (L-023, L-024; screenshots in
  `docs/audit/2026-09-28/l023/`, `l024/`) and the Sprint 23 UI tests' screenshots.
- **The walk fixed:** the eight walk defects above (undo banner, filter chips, refund row names, Quick Add merchant,
  split/duplicate/keypad Done, net-of-refunds label, detector noise, Goals +), the Spanish plural test, and the board
  drag the Mac kept catching (closed in L-033).
- **Still needs the owner (L-034 walk pending):** F7's notification actually arriving at 80 %/100 %, bulk delete → Undo
  by hand; A-023 needs a real finger (WALK-QUEUE).
- **Open decisions:** data-safety S5 (months before a budget's start show its current limit) and S6–S8 stay open, not
  blocking; the delete confirmation before the Undo banner is kept.
