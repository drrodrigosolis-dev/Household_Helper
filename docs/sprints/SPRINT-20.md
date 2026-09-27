# Sprint 20 — v1.1: refunds

Owner request 2026-09-27 (decision 29): tap a purchase, choose Refund; the money comes back and the purchase stays on
record. Owner answers: a linked refund (not "mark cancelled"), partial refunds allowed, and for a wishlist purchase ask
whether to keep the item on the wishlist or remove it.

## Why a linked refund, not "Cancelled"
Marking a purchase cancelled already exists (its editor's Status) but rewrites the past: a September purchase returned
in October would vanish from September's spending, budget and balance history. A refund is money coming back on the
day it comes back, so both records stay and every past figure stays true (§5 of CLAUDE.md: never rewrite history).

## Ground rules
- **First schema change since the freeze.** SchemaV2 = SchemaV1 plus one optional field on `TransactionRecord`
  (`refundOfTransactionID`), a lightweight stage V1→V2, and a test that opens a real on-disk V1 store with data under
  V2 and finds every record intact. `household-migration-audit` and `household-data-safety-review` before "done".
- **Before the owner installs this build:** Settings › Data › Back up now (first migration of real data). The install
  step in `TO-LOCAL.md` makes this step 1.
- Money stays `Int64` minor units; all refund arithmetic in Core with tests.

## Decisions (defaults set by the cloud session; owner may overrule)
1. **What a refund is:** a new transaction type `refund` (money in), linked to exactly one expense. Same account,
   currency and category as the purchase. It raises the balance like income but is **not income**: income totals
   exclude it, and it lowers the purchase's category spending in the refund's own month.
2. **Where:** the purchase's editor (tap the transaction) gets **Refund…**, opening a sheet (no new screen, §24):
   amount (pre-filled with what is left to refund), date (today; not before the purchase), status (Posted or Pending),
   optional note. The sheet shows "Paid $120.00 · already refunded $40.00".
3. **Partial refunds:** any amount above zero up to what is left (price − earlier non-cancelled refunds); several
   refunds allowed until the full price is back. Then Refund… is replaced by "Fully refunded".
4. **What can be refunded:** posted or pending expenses only (not income, transfers, refunds or cancelled records).
5. **How it reads:** the purchase shows "Refunded" or "Refunded $40.00 of $120.00"; a refund row shows
   "Refund · <purchase note or category>" with + amount, and opens the purchase from its editor.
6. **Protecting history:** a purchase with refunds cannot be deleted, cancelled, turned into another type, moved to
   another account or currency, or lowered below what was refunded (message says to delete the refunds first).
   A refund can be edited (amount within the limit, date, status, note) or deleted (with confirmation).
7. **Budgets and analytics:** a category's spending in a month = its expenses − its refunds in that month, shown as
   zero when refunds exceed spending (a later-month return); Analytics lists refunds as their own line.
8. **Wishlist purchase:** when a refund brings the refunded total to the full price, a dialog asks: **Keep on
   wishlist** (item back to Wanted; the old purchase stays in history, unlinked from the item so it can be bought
   again) or **Remove from wishlist** (item archived with its history). A partial refund changes nothing on the item.
9. **Not from elsewhere:** Quick Add, CSV import, recurring items and Shortcuts don't create refunds. CSV export and
   backups include them.
10. **Backup format v3:** adds `refundOfTransactionID` and the `refund` type; reads v1–v3; older app versions refuse a
    v3 file with the existing "made by a newer version" message.
11. **Themes:** the celebration does not play for refunds.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | SchemaV2 + migration stage + on-disk V1→V2 migration test | ☐ | tests |
| 2 | Core: `refund` type, `refundTransaction`, limits and protections (tests) | ☐ | tests |
| 3 | Core: balances, budgets, analytics, dashboard count refunds correctly (tests) | ☐ | tests |
| 4 | Core: wishlist keep/remove on a full refund (tests) | ☐ | tests |
| 5 | Backup v3 + CSV export (tests, round trip) | ☐ | tests |
| 6 | App: Refund… sheet, labels, protections' messages, wishlist dialog; Spanish | ☐ | ☐ |
| 7 | UI tests: full and partial refund, wishlist keep/remove; screenshots light/dark/largest text | ☐ | ☐ |

Lanes: none (schema and money; one author).

## Close-out
☐ CI green · ☐ migration audit · ☐ data-safety review · ☐ walk (`docs/walk/sprint-20/`) · ☐ owner backup before
install · ☐ PROGRESS + PR
