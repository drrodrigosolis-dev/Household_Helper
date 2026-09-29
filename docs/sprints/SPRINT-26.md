# Sprint 26 — v1.1: task time and reminder default time (CI green; owner walk pending)

Owner request 2026-09-28: tasks have a date; add an optional time. Reminders fire at the task's time, and a task
without a time fires at a "Reminder default time" set in Settings. Until now every reminder fired at 9:00.

## Decisions (lead, owner may overrule)
- Schema: a new **SchemaV5** (TaskItem gains `dueTimeMinutes: Int?`), not an edit to V4. V4 isn't on the owner's
  phone yet, but a local Simulator has V4 data, and an installed version never changes. The phone goes V3 → V4 → V5
  in one update, with lightweight stages only.
- Recurring bills also use the default time (still the day before). Recurring tasks keep their time.
- Backups carry the time; older backups restore with no time.
- Not included: Quick Add parsing a time ("tomorrow 3pm"), unless the owner asks. (The owner asked: built post-sprint,
  see below.)

## Items
| # | Item | Built | Walked |
|---|---|---|---|
| 1 | SchemaV5 + v4ToV5 stage; V1–V3 stay pinned; migration audit recorded | ☑ | ☑ walked by its tests (migration tests; `FrozenSchemaTests` pins V4/V5 with the Mac's hashes, L-026, 2a9cb79) |
| 2 | Task time in the service, recurring occurrences, backup format | ☑ | ☑ walked by its tests (task service, recurring copies, backup v6 round trip; clock-change tests, L-028) |
| 3 | ReminderPlanner: task time, default time, bills at the default time, DST-safe | ☑ | ☑ walked by its tests (`ReminderSyncTests`, planner, DST crossings); a real reminder at the task's time: L-034 walk pending |
| 4 | Task editor time picker; time on the card and detail | ☑ | ☑ `TaskTimeUITests` screenshots (editor, board card) |
| 5 | Settings › Reminders › Reminder default time; reschedules | ☑ | ☑ `TaskTimeUITests` screenshots (setting changed); that it moves an untimed task's reminder: L-034 walk pending |
| 6 | Tests: planner, migration, backup round trip, UI | ☑ | ☑ the tests themselves: green in 36599247241; the Mac's unit run 625/626 before 06231ab (L-028), UI 88/88 (L-033) |

## Close-out (2026-09-29)
☑ CI green: run 36599247241 on `dba6f9e` (lint, build, unit, UI 88/88); the Mac's full UI suite 88/88 on the same code
(L-033). ☑ migration audit (84167b4). ☑ data-safety review, fixes merged (319e76e). ☑ PROGRESS row · ☑ PR #2 body.

- **Shipped:** SchemaV5 (`TaskItem.dueTimeMinutes`) with a lightweight V4 → V5 stage, installed with `f183138` and
  pinned since `2a9cb79`; task time in the service, recurring copies and backup v6; the reminder planner at the task's
  time or the Settings default time, bills at the default time; the editor's time picker, the time on card and detail;
  Settings › Reminders › Reminder default time; Spanish (f183138).
- **Walked:** the domain items by their tests; the editor, card and setting by `TaskTimeUITests` screenshots.
- **The walk fixed:** the clock-change tests used zones the Mac's Simulator has no DST data for (06231ab, L-027/L-028);
  the typed test arguments that timed out the compiler (2678786, 6701667).
- **Still needs the owner (L-034 walk pending):** a timed task reminding at its time, and a Reminder default time
  change moving an untimed task's reminder, on the phone; the Release install of `dba6f9e`-level code on the phone.
- **Open decisions:** none new (the lead's decisions above stand unless the owner overrules them).

### Post-sprint fixes (2026-09-28/29), all in `dba6f9e`
- **Tour accessibility audit fixes** (c7734ea): VoiceOver focus on each stop's header with the app behind hidden,
  full-size Skip/Next, callout sizing and docking at large text, the Tasks stop names Move to….
- **Sprint 26 data-safety fixes B1, B2, S1–S5** (merge 319e76e): due times survive clock changes and the editor keeps
  stored times (388c559); reminder refreshes run one at a time behind a testable notification center, so a quick
  second default-time change has the last word (3861755); the V3 migration test carries a repeating task with no time
  (3fd4663); SchemaV1's frozen note corrected (64f502f).
- **Entry text reads times of day and income/expense phrases** (e8b00b0, merge ebc972d; spec §25.2 in 085c6f5): one
  time parser for Quick Add, batch task lines and Siri tasks; multi-word income/expense phrases in English and Spanish.
- **Tasks board** (root cause from the board logs in `docs/walk/l031/`–`l033/`): a ScrollPosition so a drag settles onto
  a column (9be3e5c); a drop lands at most one column from its source (39cd304); spring-load one column from the source
  and a drag with no drop settles back (d213c4f); the board holds still during a drag and spring-loading is removed
  (1f51430). The Mac's L-033: three fast drags, a slow drag and a left-edge drag all clean, `TasksUITests` ×2 and the
  full suite 88/88.
- **Test fixes:** tips reach Budgets by its segment and add a budget first (199bbc8, 600db9a, f36b82e); the split info
  is one accessibility element (f36b82e); tour stop 1 at accessibility sizes (dcfbdc7); the scroll helper sees visible
  labels and the large-text walk swipes further (600db9a); spring-load, scroll-helper, spotlight and saved-search
  fixes for CI run 36453971771 (719fe0d).

Decisions:
- Plain "at 3" is not a time: a bare number is never read as a time ("3pm", "15:30", "at 3pm", "a las 3" are).
- A Quick Add time later than now with no day word means yesterday (Quick Add never records a time after now; tasks
  take today while the time is ahead, else tomorrow).
- Only "for"/"por" is dropped after a type phrase ("I paid 40 for gas" → "gas"); other words stay in the description.
- One column per drag, and spring-loading removed. Why: the L-031/L-032 logs showed no drop fires when the board moves
  under a still finger (the system's drag auto-scroll or our spring-load), so the card stayed put or the board ended on
  the wrong column. The board now holds still during a drag; the next column peeks in on the right and the previous one
  has the edge strip on the left, both drop targets.
