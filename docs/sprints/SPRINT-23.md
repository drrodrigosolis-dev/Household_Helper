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
| A-003 | medium | owner (default: fix) | Import maps Description → Merchant for new imports; existing rows untouched. | ☐ | ☐ |
| A-004 | medium | fix | Shared keyboard Done button + interactive dismiss on every form with a number pad. | ☐ | ☐ |
| A-005 | medium | fix | Debounced search, filtering off the per-keystroke path; measured by a UI performance test. | ☐ | ☐ |
| A-006 | medium | owner (default: fix, scoped) | Import suggests a category from merchant memory (the category the same merchant last had), shown in the preview; plus an "Uncategorized" filter. No new AI. | ☐ | ☐ |
| A-007 | medium | owner (default: fix, scoped) | Multi-select in Transactions: Set category / Delete (confirmed). | ☐ | ☐ |
| A-008 | medium | not a bug (pending finger) | RefundUITests opens Refund… on a wishlist purchase with a real synthesized tap and passes on CI; likely the tap tool (the audit's own caveat). Local to confirm with a long press. | — | ☐ |
| A-009 | medium | not a bug (pending finger) | BudgetsUITests taps `budgets.addEmpty` and passes; same caveat. | — | ☐ |
| A-010 | low | fix | Account picker in Mark Purchased (with more than one account). | ☐ | ☐ |
| A-011 | low | fix | Re-tapping the Budget tab at the top restores the large title and search. | ☐ | ☐ |
| A-012 | low | fix | Re-tapping a tab pops it to its root. | ☐ | ☐ |
| A-013 | low | owner (default: fix) | Hide the floating + on Recurring and Budgets (their toolbar + stays). | ☐ | ☐ |
| A-014 | low | fix | Hide the floating + while searching; bottom inset already on lists (re-check Budget). | ☐ | ☐ |
| A-015 | low | fix | Transaction editor Save disabled until something changes. | ☐ | ☐ |
| A-016 | low | fix | "Recorded in Budget" opens the expense. | ☐ | ☐ |
| A-017 | low | owner (default: backlog) | Month history for budgets is a feature. | — | — |
| A-018 | low | owner (default: backlog) | Interactive Analytics is a feature. | — | — |
| A-019 | low | fix | Add actions on the Wishlist and Recurring empty states. | ☐ | ☐ |
| A-020 | low | fix | Recurring editor lists the next three dates. | ☐ | ☐ |
| A-021 | low | owner (default: rename the row to "Data") | §24 names the screen "Data"; make the row match. | ☐ | ☐ |
| A-022 | low | fix | Account delete checks use first, then confirms. | ☐ | ☐ |
| A-023 | low | needs finger | Carried from L-018; WALK-QUEUE. | — | ☐ |

Appendix feature ideas (1–8): owner decision, not in this sprint.

## Close-out
CI green on the head with every fix; local closes each fixed ID; PROGRESS row; PR #2 body.
