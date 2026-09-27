# Sprint 17 — v1.1: batch add

Owner request 2026-09-27 (decision 26 in `docs/PROGRESS.md`): "a batch creation, so I can quickly add all the
actions and wishlist items I have so far". Owner answers: paste a list, one type per batch, ship in v1.1.

## Ground rules
- **No schema change.** SchemaV1 freezes with the first install on the owner's iPhone (L-013, same day). Batch add
  only creates existing records (`TaskItem`, `WishlistItem`).
- One save per batch: every valid line is added, or nothing is (a failed save leaves the store unchanged).

## Decisions (defaults set by the cloud session; owner may overrule)
1. **Entry:** "Add several…" in the Tasks and Wishlist toolbars opens a sheet already set to that type (a sheet like
   CSV import, not a new screen, §24). A Tasks | Wishlist picker in the sheet can switch it.
2. **Lines:** one item per line; blank lines ignored; list markers stripped (`-`, `*`, `•`, `–`, `[ ]`, `☐`, `1.`,
   `1)`), so a list pasted from Notes works as is. At most 200 items per batch.
3. **Task line:** the title is the line; one date word sets the due date and is removed: `today`/`hoy`,
   `tomorrow`/`mañana`, a weekday (`friday`, `fri`, `viernes`, `vie`) = its **next** occurrence (today counts).
   Numbers stay in the title ("buy 2 lightbulbs"). New tasks go to the first column, medium priority, in paste order.
4. **Wishlist line:** the first plain number is the price ("250 new bike", "$1,200 sofa"); no number = price unknown;
   a `#tag` picks an expense category like Quick Add; the rest is the name. Status wanted, medium priority.
5. **Preview:** every line is listed before saving: what it becomes (title and due date, or name, price and
   category) or why it's skipped (no text left, name too long, price over the limit). The button says "Add N tasks"
   and adds only the valid lines. The preview follows the text as it is edited; no per-row editing.
6. **Quick Add task mode** reads dates with the same task grammar. Before, "call plumber friday" was due *last*
   Friday (the expense grammar looks back) and "buy 2 lightbulbs" lost the 2.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | Core: `TaskLineParser`, `WishlistLineParser`, `BatchAddPlanner` (tests) | ☐ | tests |
| 2 | Core: `createTasks(_:now:)`, `createWishlistItems(_:now:)`, one save each (tests) | ☐ | tests |
| 3 | Quick Add task mode uses `TaskLineParser` | ☐ | ☐ |
| 4 | App: `BatchAddView` sheet + toolbar entries; Spanish strings | ☐ | ☐ |
| 5 | UI test: paste tasks and wishlist items, preview, save; screenshots light/dark/largest text | ☐ | ☐ |

Lanes: none (items 1–2 are shared by 3–5; one author).

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-17/`) · ☐ data-safety review (batch save) · ☐ PROGRESS + PR
