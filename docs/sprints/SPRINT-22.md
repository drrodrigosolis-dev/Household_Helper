# Sprint 22 — v1.1: recurring purchases

Owner request 2026-09-28 (decision 31): "allow not only recurring payments, but also purchases" — answer: purchases
that repeat (groceries every week) recorded as purchases rather than bills.

## Decisions (defaults; owner may overrule)
1. A recurring item is a **Bill** (today's behavior) or a **Purchase**. A purchase names a store (merchant) and a
   category; its occurrences post as expenses with that merchant, so they count under the store in Analytics.
2. Bill reminders stay for bills; a purchase gets no "due" reminder by default (it's something you do, not owe).
3. Upcoming and Recurring show purchases with a cart icon and the store; the projection counts both the same way.
4. **Storage:** `RecurringTransaction` gains `kind` (bill/purchase) and `merchantName`. SchemaV2 was installed on the
   owner's iPhone at `fd7e67e` (owner-directed, L-017 report), so it is frozen too: this is **SchemaV3** with a
   lightweight V2→V3 stage (`SchemaV3.RecurringTransaction`; V1 and V2 keep the shared V1 class), an on-disk V2→V3
   migration test (existing series become bills), and backup v4 (reads v1–v4).
5. Quick Add stays one-off; recurring purchases are made in Budget › Recurring (Add → Purchase).

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | Model (SchemaV2) + service + backup + tests | ☐ | tests |
| 2 | Recurring editor: Bill / Purchase, store field; rows and Upcoming | ☐ | ☐ |
| 3 | Posting a purchase occurrence records the merchant; reminders only for bills | ☐ | ☐ |
| 4 | UI tests + screenshots | ☐ | ☐ |
