# Sprint 23 — v1.1: fixes from the local full audit

Input: `docs/audit/2026-09-28/FINDINGS.md` (local, audited `338a877`, 23 findings). Owner prompt 2026-09-28: every
finding gets an outcome; verify against the code first; data/money first; a test per fixed bug; one owner-questions
message with defaults; local re-verifies by finding ID.

## Ground rules
- SchemaV1–V3 are frozen (FrozenSchemaTests); a stored-model change would be SchemaV4 (none planned).
- Data-sensitive fixes (A-001, A-003) pass household-data-safety-review.
- Local re-verifies in batches (one L-item per round), answering closed / reopened / not verified per ID.

## Outcomes
| ID | Sev | Outcome | Notes | Built (CI) | Verified (local) |
|---|---|---|---|---|---|
| A-001 | blocker | **fix** | Root cause: candidates are rebuilt from the start's whole seconds, so a start carrying fractions of a second (every "now") dropped its first occurrence. Engine compares against the whole-second start; test per rule. Also: the editor's Starts defaults to start of today and lists the next dates (A-020). | ☐ | ☐ |
| A-002 | medium | fix | Recent activity drops purchased wishlist items (their expense row stands for them). | ☐ | ☐ |
| A-003 | medium | fix (owner: default) | Import maps Description → Merchant for new imports; existing rows untouched. | ☐ | ☐ |
| A-004 | medium | fix | Shared keyboard Done button + interactive dismiss on every form with a number pad. | ☐ | ☐ |
| A-005 | medium | fix | Debounced search, filtering off the per-keystroke path; measured by a UI performance test. | ☐ | ☐ |
| A-006 | medium | fix (owner: default) | Import suggests a category from merchant memory (the category the same merchant last had), shown in the preview; plus an "Uncategorized" filter. No new AI. | ☐ | ☐ |
| A-007 | medium | fix (owner: default) | Multi-select in Transactions: Set category / Delete (confirmed). | ☐ | ☐ |
| A-008 | medium | not a bug (pending finger) | RefundUITests opens Refund… on a wishlist purchase with a real synthesized tap and passes on CI; likely the tap tool (the audit's own caveat). Local to confirm with a long press. | — | ☐ |
| A-009 | medium | not a bug (pending finger) | BudgetsUITests taps `budgets.addEmpty` and passes; same caveat. | — | ☐ |
| A-010 | low | not a bug (local to re-check) | The sheet already shows "Paid from" when there is more than one active account (`wishlist.purchase.account`); the walk's fresh install had one. | ☐ | ☐ |
| A-011 | low | won't fix | iOS's own tab re-tap scrolls to top; there is no public API to re-expand a collapsed large title or show a hidden search field. A pull-down shows both (standard iOS). | ☐ | ☐ |
| A-012 | low | fix (local to verify) | More uses a path the router clears on re-tap. Needs a check that iOS 26 reports the re-tap to the selection binding. | ☐ | ☐ |
| A-013 | low | fix (owner: default) | Hide the floating + on Recurring and Budgets (their toolbar + stays). | ☐ | ☐ |
| A-014 | low | fix | Hide the floating + while searching; bottom inset already on lists (re-check Budget). | ☐ | ☐ |
| A-015 | low | fix | Transaction editor Save disabled until something changes. | ☐ | ☐ |
| A-016 | low | fix | "Recorded in Budget" opens the expense. | ☐ | ☐ |
| A-017 | low | **feature, this sprint (owner)** | Budgets: previous months with spent/limit and rollover. | ☐ | ☐ |
| A-018 | low | **feature, this sprint (owner)** | Analytics: tap a slice/bar to see its transactions; change vs last month. | ☐ | ☐ |
| A-019 | low | fix | Wishlist empty state gets "Add item" (`wishlist.addEmpty`); Recurring already had one (`recurring.addEmpty`). | ☐ | ☐ |
| A-020 | low | fix | Recurring editor lists the next three dates; Starts defaults to the start of today. | ☐ | ☐ |
| A-021 | low | fix (owner: default, row renamed "Data") | §24 names the screen "Data"; make the row match. | ☐ | ☐ |
| A-022 | low | fix | Account delete checks use first, then confirms. | ☐ | ☐ |
| A-023 | low | needs finger | Carried from L-018; WALK-QUEUE. | — | ☐ |

## Features added by the owner (2026-09-28: "all this sprint")
| # | Feature | Plan | Built (CI) | Verified |
|---|---|---|---|---|
| F1 | Categories learned from manual edits, applied to imports and Quick Add | `Merchant.defaultCategoryID` (exists, never set until now); import lane | ☐ | ☐ |
| F2 | Recurring detection from history | Core finds merchant+amount repeating weekly/monthly; Recurring shows "Make it a bill?" suggestions | ☐ | ☐ |
| F3 | Undo for delete and bulk edits | Undo banner; restores the same records (same ids, links) | ☐ | ☐ |
| F4 | Duplicate and split transactions | Duplicate: no schema. Split: **SchemaV4** (optional `splitGroupID` on TransactionRecord), parts sum to the original | ☐ | ☐ |
| F5 | Month-end summary | Analytics section: last month spent vs budgets, top categories, goals | ☐ | ☐ |
| F6 | Search filters + saved searches | Amount range, date range, account; saved searches in device settings (not SwiftData) | ☐ | ☐ |
| F7 | Budget alerts at 80 % / 100 % | Local notifications (names only), reusing the reminders plumbing | ☐ | ☐ |
| F8 | Import presets per bank | Column mapping/date format/sign remembered per preset, in device settings | ☐ | ☐ |

Waves: wave 1 = the fixes (lanes: import A-003/A-006/F1; list A-005/A-007/A-013/A-014/A-015 + Uncategorized filter; lead:
the small ones). Wave 2 = features, after wave 1 is merged and pushed.

## Close-out
CI green on the head with every fix; local closes each fixed ID; PROGRESS row; PR #2 body.
