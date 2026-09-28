# Sprint 26 — v1.1: task time and reminder default time (building)

Owner request 2026-09-28: tasks have a date; add an optional time. Reminders fire at the task's time, and a task
without a time fires at a "Reminder default time" set in Settings. Until now every reminder fired at 9:00.

## Decisions (lead, owner may overrule)
- Schema: a new **SchemaV5** (TaskItem gains `dueTimeMinutes: Int?`), not an edit to V4. V4 isn't on the owner's
  phone yet, but a local Simulator has V4 data, and an installed version never changes. The phone goes V3 → V4 → V5
  in one update, with lightweight stages only.
- Recurring bills also use the default time (still the day before). Recurring tasks keep their time.
- Backups carry the time; older backups restore with no time.
- Not included: Quick Add parsing a time ("tomorrow 3pm"), unless the owner asks.

## Items
| # | Item | Built | Walked |
|---|---|---|---|
| 1 | SchemaV5 + v4ToV5 stage; V1–V3 stay pinned; migration audit recorded | ☐ | ☐ |
| 2 | Task time in the service, recurring occurrences, backup format | ☐ | ☐ |
| 3 | ReminderPlanner: task time, default time, bills at the default time, DST-safe | ☐ | ☐ |
| 4 | Task editor time picker; time on the card and detail | ☐ | ☐ |
| 5 | Settings › Reminders › Reminder default time; reschedules | ☐ | ☐ |
| 6 | Tests: planner, migration, backup round trip, UI | ☐ | ☐ |
