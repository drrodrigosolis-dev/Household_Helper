# Sprint 18 — v1.1: narrower task columns, focus follows the task

Owner request 2026-09-27 (decision 27): columns "use only 2/3 of the screen", and a task dragged to the next column
brings that column into focus. Owner answer: also auto-scroll while dragging.

## Decisions (defaults set by the cloud session; owner may overrule)
1. **Width:** every column is 2/3 of the board's width. **Owner decision (walk, 2026-09-27): aligned with the left
   edge** (16 pt margin), the next column peeking in on the right; centering left an empty strip beside the first
   column. The previous column is then out of sight, so the left-edge margin is a drop strip: resting a dragged task
   there brings the previous column back, and dropping there moves the task into it. Same at every text size.
2. **Focus after a move:** after a drop into another column, and after "Move to…" from the task menu, the board
   slides that column to the left edge. Moving within a column doesn't scroll.
3. **Auto-scroll while dragging (spring-loading):** hovering a dragged task over a peeking column for 0.6 s brings it
   into focus (the left edge does the same for the previous column), so a task can travel across several columns in one drag, in either direction. SwiftUI has no edge
   auto-scroll; spring-loading on the peeking column is the reliable equivalent (like the Home Screen). Known
   trade-off: the slide puts the *next* column under a finger that stays still, so the column a drop would land in
   is outlined in the accent color; releasing late on the far edge drops one column further (device walk item).
4. **Reduce Motion:** the board jumps instead of sliding.
5. No data change: this is layout only (SchemaV1 frozen).

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | Board: 2/3-width columns at the left edge (owner decision), scroll position | ☐ | ☐ |
| 2 | Focus the destination after a drop or Move to… | ☐ | ☐ |
| 3 | Spring-loaded hover while dragging | ☐ | ☐ (drag feel: device) |
| 4 | UI test: column width, drag to the next column focuses it; screenshots | ☐ | ☐ |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-18/`) · ☐ PROGRESS + PR
