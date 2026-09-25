---
name: household-sprint
description: Run a Household Hub sprint — one spec §21 phase (or an owner-supplied batch of items) planned, built, verified by CI, walked, and recorded without prompting the owner between items. Use when starting or resuming a phase, or when the owner hands over a batch of features/fixes.
---

# household-sprint

Adapted for this repo from the owner's PersonalOS sprint process. The plan file and git are the memory; the
session's context is a scratch buffer.

## 1. Ask first, then run
- Number the items (a phase's §21 bullets, or the owner's list; recount, the brief's count is often wrong).
- Every doubt goes into **one** message before research: vague items, schema changes, what "done" means, each with
  a recommended default, ending *"reply with answers, or 'run' to take every default."* A doubt found later is sent
  when found; meanwhile work on what does not depend on it.
- Write `docs/sprints/SPRINT-<n>.md` (ground rules, items with ☐, lane table, close-out block), commit it, and start
  building in the same turn. The answers were the go; there is no second confirmation.

## 2. Build
- Sprint = one §21 phase; the §28 gate holds: the previous phase must be CI green before this one starts.
- **Commit the moment something is coherent; push at every stopping point.** Cloud containers are reclaimed and
  credits end; unpushed work is lost work.
- **Lanes** (parallel agents, `Agent` with `isolation: "worktree"`): none when files are shared (Phase 2);
  otherwise 3 at once, 4 at most, split by file ownership. Lanes cannot build (no Xcode in cloud sessions), so
  they are merged into `build/v1` one at a time and CI verifies each merge. Sonnet by default; Opus only where a
  wrong call is silent and expensive (schema/migration, money/accounting correctness, navigation state). Each lane
  reports what it could **not** wire (file + the one line needed); grep for that call site at merge.
- Verify claims (a plan, audit, or lane report saying "X is broken/slow/missing") by reading the code first.
- Read every merge that touched a shared file: `git diff <before> HEAD -- <file>`.

## 3. Verify
- `household-verify` on every push. CI green on the head that contains an item is required before ☑ "built".
- Data-sensitive items also pass `household-data-safety-review`; schema changes `household-migration-audit`.

## 4. The walk — the sprint ends only after it
☑ "walked" means **seen**, not inferred from green tests.
- **Cloud session (no Xcode):** each user-facing item has an XCUITest that drives it and attaches a screenshot
  (`XCTAttachment`, lifetime `.keepAlways`). Download the run's artifact, open every screenshot, and check it
  against the item's expected result (light and dark, large Dynamic Type where relevant).
- **Owner's Mac:** walk every item on the Simulator with control of the computer (the owner has authorized it);
  if the approval card times out or the owner is using the machine, message the owner to pause, wait, walk everything in
  one sitting, then say when it is safe again. Verify writes by data where possible.
- A defect found on the walk is fixed on the spot (fix → push → green → re-walk), never deferred.
- `docs/WALK-QUEUE.md` holds only what no automation can reach from the current environment (real Face ID, drag
  feel, physical device), each with numbered steps and the expected result, for the next Mac walk.
- Domain-only items (no UI) are "walked" by their tests; say so in the plan.

## 5. Close-out
1. Owed cross-item wirings, then CI green on the final head.
2. Walk (section 4).
3. Records: the sprint plan's close-out block, `docs/PROGRESS.md` row, the PR description mirror, research-log
   entries for any decision. Sprint history does not go into CLAUDE.md (durable rules only).
4. Tree clean, pushed. Final message: what shipped, what was walked and seen, what the walk fixed, what still
   needs the owner and why, open decisions.

## Budget rules
- **Quiet hours 05:00–11:00 America/Vancouver:** no parallel agents, no heavy work; do cheap work or stop and
  resume from the plan after 11:00.
- Never `cat` logs or diffs; grep, `--stat`, `tail`, `xcresulttool` summaries.
- A rate limit or crash: resume from `git log` + the plan file. Never discard drafted work.
