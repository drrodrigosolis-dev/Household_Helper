# Sprint 10 — v1.1: Multiple accounts + transfers

Owner decisions 13 and 16 (`docs/PROGRESS.md`): the owner answered "run" to the 11 questions below, so every default
is the decision. SchemaV1 is still editable (it freezes at the first install on the owner's device), so accounts go
into SchemaV1 directly; no migration stage is needed yet. Built serially during quiet hours, then in lanes.

## Decisions (owner: "run" = every default)
1. **Kinds:** bank, savings, credit card, cash. A credit card's balance is shown as the amount owed; the household
   total is what the accounts hold minus what is owed (balances are signed; a card's is normally negative).
2. **Existing baseline:** the household starting balance becomes the first account, "Main account"; every account has
   its own starting balance and as-of date. Onboarding and Settings › Household edit the default account's baseline.
3. **One currency:** every account uses the household currency (per-account currency would reopen §6.3).
4. **Archive, not delete:** an account with transactions or recurring items can only be archived; an unused one can be
   deleted. The default account can be neither until another is the default.
5. **Transfer:** one record, from account → to account. Never income or spending (Analytics, budgets, CSV totals); the
   household total is unchanged by it. No category, no merchant.
6. **Recurring transfers** are allowed (e.g. a monthly move into savings).
7. **Screens:** More › Settings › Accounts (list, editor, archive, default); a Dashboard Accounts card whose rows open
   Budget filtered to that account; an Account filter in Budget; no new tab (§24's five tabs stay).
8. **Entry:** Quick Add and the Log Transaction shortcut use the default account; Quick Add's details and the
   transaction editor can pick another. Transfers are made from Budget › New transfer and the recurring editor.
9. **Wishlist purchase** pays from the default account; the purchase sheet can pick another.
10. **Widget** shows the household total.
11. **Backups:** format v2 (accounts, a transaction's account, transfer target, the default account). v1 backups still
    restore, with everything in "Main account" built from the v1 starting balance. CSV export adds Account and To
    account columns.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `Account` model + kinds; `accountID` / `transferAccountID` on transactions and series; default account in settings | ☑ | tests |
| 2 | Per-account and household balances (current / pending impact / projected) in Core, transfers neutral | ☑ | tests |
| 3 | Account service: create, edit, archive, delete-if-unused, set default; onboarding + Household use the default | ☑ | tests |
| 4 | Transfers: drafts, validation, create/edit, recurring transfers, materialize, delete | ☑ | tests |
| 5 | Backup v2 + v1 restore into "Main account"; validator rules; CSV columns | ☑ | tests |
| 6 | Settings › Accounts screens | ☑ | ☐ |
| 7 | Dashboard Accounts card; Budget account filter; account on rows when >1 account | ☑ | ☐ |
| 8 | Account pickers: Quick Add details, transaction editor, recurring editor, wishlist purchase; New transfer sheet | ☑ | ☐ |
| 9 | Data-safety review + migration audit (SchemaV1 edit, backup v2) | ☑ | — |

## Close-out
☑ CI green: run 36251732218 on `e5ddfb7` (review fixes; run 36251261145 on `ffd3b8a` before them) · ◐ walk
(`docs/walk/sprint-10/run-36251261145`: light and dark seen and correct; the largest-text Accounts row broke words,
fixed in `f17d88a`, re-walk on its green run) · ☑ data-safety review (3 blocking + should-fixes, all fixed) ·
☑ migration audit (SchemaV1 edited in place, owner decision 15) · ☐ PROGRESS + PR
