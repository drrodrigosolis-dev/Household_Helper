# Sprint 3 — Phase 4: Wishlist

Planned 2026-09-25 while the owner was away with full authorization; recommended defaults taken and listed below
for review. Starts only once Phase 3 is CI green and walked (§28). Binding: §7.7, §8.1–8.2, §24.2 Wishlist row,
§24.3 (Quick Add Wishlist type), §5.5 (images).

## Defaults taken (owner may overrule)
1. `Priority` is `low / medium / high`, shared with Phase 5 tasks (§7.7 and §7.8 name it without values).
2. Images: optional, picked with PhotosUI, stored by an `ImageStore` under Application Support/Media/Wishlist with a
   thumbnail (§5.5); only the relative reference is persisted. No camera capture in v1.
3. "Mark Purchased" asks for the actual price (prefilled with the estimate), date, and category, then creates exactly
   one expense with source `wishlistPurchase`, links both ways, and sets status `purchased` in one save (§8.1).
4. Deleting a purchased item never deletes its transaction; the dialog offers Archive or Delete item only (§8.2).
   Deleting the linked transaction from Budget reverts the item to `wanted` (keeps history consistent).
5. Wishlist screen: filter chips (priority, status), list/grid toggle remembered per device (`@AppStorage`, a UI
   preference outside backups per §7.11), cards with thumbnail, name, priority, estimated price.
6. Quick Add gains the Wishlist segment: the text's amount becomes the estimated price, the description the name.
7. No lanes (same reasons as Sprint 2).

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | `WishlistItem` model, `WishlistStatus`, `Priority`; schema update | §7.7 | ☐ | tests |
| 2 | `WishlistService`: create/update/archive/delete with §8.2 rules | §7.7, §8.2 | ☐ | tests |
| 3 | Purchase conversion: one atomic linked expense, never duplicated | §8.1 | ☐ | tests |
| 4 | `ImageStore` (save, thumbnail, delete) with in-memory test double | §5.5 | ☐ | tests |
| 5 | Wishlist screen: chips, list/grid, cards | §24.2 | ☐ | ☐ |
| 6 | Item detail + editor + Mark Purchased flow | §24.2, §8.1 | ☐ | ☐ |
| 7 | Quick Add Wishlist segment | §24.3 | ☐ | ☐ |
| 8 | Dashboard recent activity includes wishlist changes | §24.2 | ☐ | ☐ |

## Close-out
☐ CI green on final head · ☐ walk screenshots saved to `docs/walk/sprint-3/` and reviewed · ☐ data-safety review
(purchase atomicity, deletion) · ☐ PROGRESS + PR · ☐ WALK-QUEUE
