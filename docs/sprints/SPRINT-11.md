# Sprint 11 — v1.1: Category budgets

Owner decisions 13 and 17 (`docs/PROGRESS.md`): every default below except rollover, which the owner set: **budgets
roll over by default, with a per-budget toggle**. SchemaV1 is still editable, so the budget model goes into it.

## Decisions
1. **What:** a monthly limit on an expense category (or one allowing both). Income categories get none. No overall
   budget; the total shown is the sum of the category limits.
2. **Month:** the calendar month in the household calendar.
3. **Counted:** posted expenses in the category; pending ones only while Analytics' "Include pending" is on;
   transfers never (they have no category); income filed under the category (a refund) does not reduce spending.
4. **Rollover (owner):** on by default, a toggle on each budget. Default taken for its meaning: it carries both ways —
   what was left unspent adds to the next month, an overspend takes from it — accumulating from the month the
   budget was created. Off = a plain monthly limit. (Owner may narrow it to "leftovers only".)
5. **History:** one limit per category for every month; changing it re-reads past months against the new limit.
   Data-safety review follow-ups (defaults taken, owner may overrule at phase end): turning rollover back on starts
   counting afresh that month, so months it was off never add carry; raising the limit re-grants every past month
   since the start (decision 5 as written, and the effect can be large); months a category spent archived still
   carry the full limit (nothing could be spent then). The start is stored as a year and month, not an instant, so
   moving the device between time zones can't shift it.
6. **Screens:** Budget tab gets a third segment, Transactions / Recurring / Budgets, with each budget's progress
   (spent, available, left or over) and add / edit / remove; a Dashboard Budgets card with the three closest to or
   over their limit, each opening that category's transactions; Analytics' category breakdown shows the limit.
7. **Warnings:** colour and wording only ("CA$40 left", "CA$25 over"); notifications wait for Sprint 14.
8. **Backups:** budgets travel in backups (optional field; older backups restore with none). Deleting a category
   removes its budget (a budget is not financial history); archiving hides it.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `CategoryBudget` model; budget math in Core (spent, carry-in, available, left/over) | ☐ | tests |
| 2 | Service: set / edit / remove, validation, report for a month; category delete/archive rules | ☐ | tests |
| 3 | Backup field + validator; CSV unaffected | ☐ | tests |
| 4 | Budget › Budgets segment (list, progress, add/edit/remove, rollover toggle) | ☐ | ☐ |
| 5 | Dashboard Budgets card; Analytics limit on category rows | ☐ | ☐ |
| 6 | Data-safety review + migration audit | ☐ | — |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-11/`) · ☐ data-safety review · ☐ migration audit · ☐ PROGRESS + PR
