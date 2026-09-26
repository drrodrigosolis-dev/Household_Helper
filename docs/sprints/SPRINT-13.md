# Sprint 13 — v1.1: Recurring tasks

Owner decision 20 (`docs/PROGRESS.md`): every default below was accepted ("take defaults, all default"). SchemaV1 is
still editable (owner decision 15), so the repeat fields go on `TaskItem` in it.

## Decisions
1. **Rules:** the recurrence rules recurring transactions use, plus a new `daily(interval:)` (also offered for recurring
   transactions). The task editor offers Never / Daily / Weekly / Every 2 weeks / Monthly / Yearly, each read off the
   due date (weekly on its weekday, monthly on its day, yearly on its month and day).
2. **Completing:** completing a repeating task on its own (moving it into Done, the Complete button, creating it in
   Done, restoring it there) adds the next task — not a column change (owner decision 21): same
   title, notes, priority and subtasks (unticked), no links, in the column it was completed from (the first column if
   it came from nowhere else). The completed task stays as history.
3. **Next date:** the rule's next date after the completed task's due date, not after the completion date. A task
   completed late gets a next task that may already be due.
4. **Ending:** turning the repeat off (or the due date off) or deleting the task ends the series; completed tasks are
   never touched. The rule moves from the completed task to the new one, so reopening and completing again adds no
   second copy.
5. **Screens:** a Repeat picker in the task editor (shown with a due date), "Repeats" on task detail, a repeat icon
   on the card.

Backups carry the rule and its time zone on each task (optional; older files have none). The validator requires a valid
rule, a known zone and a due date, and both fields together.

## Data-safety review (Sprint 13) — fixed before the gate
- B1 (tests): every path into the done column (column reorder and undo, create into Done, delete a column into Done),
  daily recurring transactions (materialize once, off-days refused, long histories, backup round trip), the
  validator's invalid-rule branch, tasks from older backups, and the `daily` stored-format fixture.
- S1: a completed task can't be given a repeat (service refuses; the editor hides Repeat), so there is never a second
  series.
- S3: the done-column change and delete-task dialogs say what happens to repeats.
- S4: if no next task can be made, the rule stays put instead of being dropped; an unknown zone falls back to the
  device's.
- S2, settled by owner decision 21: column changes (reordering the done column, deleting a column into it) complete
  tasks without adding next copies; the tasks keep their rule. Only a task completed on its own adds its next one.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `daily` rule in the engine; task repeat fields; `TaskRepeat` choices | ☐ | tests |
| 2 | Board service: next task on completion (every path into the done column), rule hand-over | ☐ | tests |
| 3 | Backup fields + validator | ☐ | tests |
| 4 | Task editor Repeat picker, detail, card icon; Daily in the recurring-transaction editor | ☐ | ☐ |
| 5 | Data-safety review | ☐ | — |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-13/`) · ☐ data-safety review · ☐ PROGRESS + PR
