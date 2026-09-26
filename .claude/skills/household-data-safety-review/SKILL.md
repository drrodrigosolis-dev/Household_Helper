---
name: household-data-safety-review
description: Review changes touching money, transactions, balances, recurrence, wishlist purchases, deletion, backup/restore, or persistence for accounting integrity and data-loss risk. Use before any data-sensitive change is considered done (§18 data-sensitive checklist).
---

# household-data-safety-review

Check and report each item as holds / violated / not applicable, with evidence (file:line or test name):

1. Money is `Int64` minor units + currency code; no `Double` in any money path; arithmetic only via the money
   module; overflow handled.
2. Balances: current = starting + posted after starting date; pending excluded; projected is deterministic over a
   bounded window; the three are never conflated (§9).
3. No duplicate financial event: wishlist purchase creates exactly one linked `wishlistPurchase` transaction in
   one atomic save (§8.1); recurring materialization cannot post the same occurrence twice.
4. Deletion rules (§8.2–8.5): no silent deletion of transactions; categories archived not hard-deleted when
   referenced; board-column deletion moves tasks first; recurring-occurrence delete offers the three choices.
5. Destructive actions have explicit confirmation copy stating consequences.
6. Backup/restore (§26): validate everything before writing; restore is transactional; no secrets in backups;
   missing media fails gracefully.
7. Secrets only in Keychain; nothing sensitive in logs.
8. Tests exist for each invariant touched. Missing test = violated.
