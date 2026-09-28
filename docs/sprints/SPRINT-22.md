# Sprint 22 — v1.1: recurring purchases

Owner request 2026-09-28 (decision 31): "allow not only recurring payments, but also purchases" — answer: purchases
that repeat (groceries every week) recorded as purchases rather than bills.

## Decisions (defaults; owner may overrule)
1. A recurring item is a **Bill** (today's behavior) or a **Purchase**. A purchase names a store (merchant) and a
   category; its occurrences post as expenses with that merchant, so they count under the store in Analytics.
2. Bill reminders stay for bills; a purchase gets no "due" reminder by default (it's something you do, not owe).
3. Upcoming and Recurring show purchases with a cart icon and the store; the projection counts both the same way.
4. **Storage:** `RecurringTransaction` gains `kind` (bill/purchase) and `merchantName`. SchemaV2 is not installed on
   the phone yet (Sprint 20 is not released), so these join SchemaV2 rather than making a V3; the V1→V2 migration
   test covers them (existing series become bills). Backup v3 carries them.
5. Quick Add stays one-off; recurring purchases are made in Budget › Recurring (Add → Purchase).

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | Model (SchemaV2) + service + backup + tests | ☐ | tests |
| 2 | Recurring editor: Bill / Purchase, store field; rows and Upcoming | ☐ | ☐ |
| 3 | Posting a purchase occurrence records the merchant; reminders only for bills | ☐ | ☐ |
| 4 | UI tests + screenshots | ☐ | ☐ |
