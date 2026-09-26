# Sprint 4 — Phase 5: Tasks

Planned 2026-09-26 while the owner was away with full authorization; recommended defaults taken and listed below
for review. Binding: §7.8–§7.10, §8.5, §24.2 Tasks row, §24.3 (Quick Add Task type), §24.5 (non-drag alternative).

## Defaults taken (owner may overrule)
1. First launch seeds three system columns: To Do, In Progress, Done. System columns can be renamed and reordered
   but not deleted; custom columns can be added.
2. Completion follows the board: the last column is the "done" column. Moving a task into it sets `completedAt`,
   moving it out clears it, and "Mark complete" moves the task there. One rule, no extra stored flag (§7.10 has none).
3. Task order uses the §7.8 `Double` sort key: a move takes the midpoint of its new neighbours, and a column is
   renumbered (1, 2, 3, …) when a gap gets too small. Columns use the §7.10 integer order, renumbered on reorder.
4. Subtasks are `SubtaskItem` rows keyed by `taskID` (the codebase links by ID, as transactions do); deleting a task
   deletes its subtasks in the same save. Tasks are not financial history, so deletion is real, after confirmation.
5. Deleting a column requires a destination column and moves its tasks first, in one save (§8.5).
6. Board: horizontally scrolling columns of cards; drag to reorder or move between columns. Every card also has a
   context menu and VoiceOver actions: "Move to…" (each column), "Move up", "Move down", Edit, Delete (§24.5).
7. Quick Add gains the Task segment: the description becomes the title, a date word ("tomorrow") the due date; an
   amount is ignored for tasks.
8. `linkedWishlistItemID` gets a picker in the task editor; `linkedTransactionID` is stored but has no v1 UI yet.
   Deleting a wishlist item clears task links to it; a stale link is dropped on save (data-safety review S3).
10. Added after the data-safety review: archived tasks keep their completion time when the done column changes, and a
    column reorder that changes the done column asks for confirmation first.
9. Dashboard recent activity adds task changes (completing the §24.2 "transactions/tasks/wishlist" list).

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | `BoardColumn`, `TaskItem`, `SubtaskItem` models; schema update | §7.8–§7.10 | ☑ | tests |
| 2 | `TaskBoardService`: seed columns, task CRUD, move/reorder with rebalance, completion rule | §7.8, §7.10 | ☑ | tests |
| 3 | Subtasks: add, toggle, reorder, delete with the task | §7.9 | ☑ | tests |
| 4 | Column add/rename/reorder/delete-with-destination | §8.5 | ☑ | tests |
| 5 | Board screen: columns, cards, drag and drop | §24.2 | ☑ | ☑ |
| 6 | Non-drag alternatives: context menu and VoiceOver actions | §24.5 | ☑ | ☑ |
| 7 | Task detail/editor with subtasks and wishlist link | §7.8, §7.9 | ☑ | ☑ |
| 8 | Quick Add Task segment; Dashboard activity includes tasks | §24.3, §24.2 | ☑ | ☑ |

## Close-out
☐ CI green on final head (built green on run 36205435799 on `9635f01`; review fixes `1c11590` pending) · ☑ walk screenshots saved to `docs/walk/sprint-4/` and reviewed · ☑ data-safety review
(column delete, cascade, links) · ☐ PROGRESS + PR · ☐ WALK-QUEUE
