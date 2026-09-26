# Sprint 13 — v1.1: Recurring tasks

Owner decision 20 (`docs/PROGRESS.md`): every default below was accepted ("take defaults, all default"). SchemaV1 is
still editable (owner decision 15), so the repeat fields go on `TaskItem` in it.

## Decisions
1. **Rules:** the recurrence rules recurring transactions use, plus a new `daily(interval:)` (also offered for recurring
   transactions). The task editor offers Never / Daily / Weekly / Every 2 weeks / Monthly / Yearly, each read off the
   due date (weekly on its weekday, monthly on its day, yearly on its month and day).
2. **Completing:** completing a repeating task (moving it into the done column, however) adds the next task: same
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
