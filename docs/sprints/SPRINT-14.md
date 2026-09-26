# Sprint 14 — v1.1: Search and local reminders

Owner decision 23 (`docs/PROGRESS.md`): every default accepted ("run"). No schema change: the reminder switches are
this device's preferences (`@AppStorage`), like the wishlist layout, and are not backed up.

## Decisions
1. **Search:** a search field on Budget › Transactions, Wishlist › Items and Tasks. It matches words in a
   transaction's notes, merchant, category and account names; a wishlist item's name and notes; a task's title,
   notes and subtasks. Case and accents are ignored; every word must match. On-device, deterministic, no AI.
2. **Amounts:** a word that reads as an amount ("47.50", "47,50") also matches a transaction or wishlist price of
   exactly that amount.
3. **Reminders:** local notifications only. A task due today at 9:00 on its due day; a recurring expense at 9:00 the
   day before. One switch each in Settings › Reminders, off until turned on; permission is asked then.
4. **Scheduling:** rebuilt from the store when the app goes to the background and when a switch changes; at most 60
   pending, soonest first (iOS allows 64).
5. **Privacy:** names only, never amounts ("Rent is due tomorrow."), since notifications show on the Lock Screen.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `SearchQuery` (Core) and search on three tabs | ☐ | ☐ |
| 2 | `ReminderPlanner` (Core), `upcomingOccurrences` shared with the Dashboard | ☐ | tests |
| 3 | `ReminderSync` + Settings › Reminders | ☐ | ☐ (device) |
| 4 | Reviews: UI (search placement), privacy (notification text) | ☐ | — |

## Close-out
☑ CI green (run 36268510203, `25afbec`) · ☑ walk (`docs/walk/sprint-14/`) · ☐ a real notification seen on the Simulator (local session) · ☑ PROGRESS + PR
