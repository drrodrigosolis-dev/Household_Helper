# Sprint 12 — v1.1: Savings goals

Owner decision 19 (`docs/PROGRESS.md`): every default below was accepted ("run"). SchemaV1 is still editable (owner
decision 15), so the goal model goes into it.

## Decisions
1. **What:** a goal has a name, a target amount (household currency), an optional target date, and an optional
   linked wishlist item (at most one goal per item).
2. **Progress:** the current (posted) balance of one account. A goal records no transactions and sets nothing aside;
   two goals on the same account show the same balance. Judgment call: credit cards can't hold a goal (their balance
   is what is owed), and an account a goal uses can't become a credit card.
3. **Monthly amount:** (target − saved) ÷ whole calendar months from today to the target date (at least 1), rounded
   up to the currency's minor unit. No date: only the amount left. Date passed and not reached: "Target date passed",
   and all of what is left is needed now.
4. **Reached:** shown as reached (green, "Reached") until the user archives it. "Mark Purchased" stays the normal
   wishlist flow; a goal never buys anything.
5. **Screens:** Wishlist tab gets an Items / Goals segment (list with progress, what is left, monthly amount; add,
   edit, archive, delete); a Dashboard Goals card with up to three active goals, opening Wishlist › Goals; a wishlist
   item's detail shows its goal, or offers "Start a Savings Goal" (prefilled with the item's name, price and date).
6. **Backups and deletes:** goals travel in backups (optional field; older backups restore with none). While a goal
   exists, deleting its account or wishlist item is refused (both can still be archived); deleting a goal changes
   nothing else. A goal locks the household currency, like every other amount.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `SavingsGoal` model; goal math in Core (saved, left, months left, monthly amount, reached, overdue) | ☐ | tests |
| 2 | Service: create / edit / archive / delete, validation, report; account and wishlist delete refusals | ☐ | tests |
| 3 | Backup field + validator; dangling wishlist links dropped on export | ☐ | tests |
| 4 | Wishlist › Goals segment, goal editor, wishlist detail goal section | ☐ | ☐ |
| 5 | Dashboard Goals card | ☐ | ☐ |
| 6 | Data-safety review + migration audit | ☐ | — |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-12/`) · ☐ data-safety review · ☐ migration audit · ☐ PROGRESS + PR
