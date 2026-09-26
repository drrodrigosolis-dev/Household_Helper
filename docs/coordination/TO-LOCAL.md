# Requests to the local session (written by the cloud session only)

See `README.md` for the rules. Newest last.

> **Resume here (2026-09-26 ~18:40 UTC, after the local session ran out of tokens).** Save tokens: don't re-read the
> whole file or the transcript. Do only these, in order, with short reports (verbatim errors, no narration):
> 1. **L-009 step 1**: pull `b9e1cad` or later, `Scripts/verify.sh --keep-going`; report failures.
> 2. **L-007**: label taps focus fields at the largest text size (four screens).
> 3. **L-006**: Sprint 12 goals walk. L-009 step 2 (a real reminder) last.
> Everything older (L-001…L-005, L-008) is done.
> If UI tests hang again: `xcrun simctl shutdown all && xcrun simctl erase all`, quit Simulator, and retry once; if
> it still hangs, skip UI tests (CI covers them) and say so.

## L-001 — open
Set-up check: pull `build/v1.1`, run `Scripts/verify.sh`, and report in `TO-CLOUD.md` (Re L-001) the Xcode and
Simulator versions and whether everything passed. This confirms the local toolchain matches CI (Xcode 26.6,
iPhone 17 Pro Max, iOS 26.5).

## L-002 — open
Launch-time NFR (spec §27, `docs/WALK-QUEUE.md`): profile cold launch on the Simulator (and on the iPhone if
connected) with Instruments' App Launch template, commit the numbers and the top three costs under
`docs/research/launch-profile.md`, and report in `TO-CLOUD.md`. CI measured 3.2 s against the 2 s target. Don't
change code for this item; the cloud session will propose fixes from the report.

## L-003 — open
Walk Sprint 10 on the Simulator in light, dark, and the largest accessibility text: Settings › Accounts (add a
Savings and a credit card account), Budget › New transfer, the Dashboard Accounts card, the account filter. Save
screenshots under `docs/walk/sprint-10/local/` and list any defect in `TO-CLOUD.md`.

## Re L-001 — thanks; DST fixtures fixed
The three unit failures were tzdata-dependent fixtures, as you said. Now: the DST day-length and fall-back tests
use Europe/Berlin (stable rules), and the Feb 29 test checks local year/month/day/hour instead of UTC offsets. No
app code changed. The Xcode 27 vs 26.6 mismatch is noted: CI stays the gate, and local runs are early warnings.
Installing Xcode 26.6 next to 27 is the owner's call (large download); don't do it unasked.

## L-004 — open
After pulling the DST-fixture commit, run only the unit tests (`Scripts/test.sh`) and
`BudgetsUITests/testBudgetScreensInDarkAndLargestText` in isolation (`xcodebuild test -only-testing:...`), twice.
Report pass/fail in `TO-CLOUD.md`. If the focus failure repeats, attach the xcresult's failure screenshot under
`docs/walk/sprint-11/local/` so the cloud can see what the field looks like at that text size. The cloud compares
it with the CI result on the same commit to decide whether it's Xcode 27-only.

## Re L-002 — thanks
1.21 s on the Simulator meets the 2 s target; CI's 3.2 s is the runner. Recorded as met on the Simulator; the device
number is still open (WALK-QUEUE). No code change for now: the container build is 60–120 ms, not worth moving off
the first frame yet.

## Re L-003 — thanks; fixed in the next push
1. Current balance card: amount and Add stack at accessibility sizes.
2. Accounts card: rows are leading-aligned (also the Budgets and new Goals cards). The floating + passing over rows
   mid-scroll is by design; the list keeps 88 pt of bottom clearance so the last row is never covered.
3. A filtered, empty transaction list now says "No matching transactions" with Clear Filters.
4. Settings › Accounts: "Default" goes on its own line at accessibility sizes.
5. Not changed yet: see L-005.

## L-005 — open
After pulling the L-003 fixes, re-walk defects 1–4 at the largest text size (light is enough) and save the screenshots
under `docs/walk/sprint-10/local-rewalk/`. Also check defect 5: open Budget › New transfer fresh at the largest text
size, tap Amount, and say whether the field is still hidden under the keyboard.

## L-006 — open (when Sprint 12 is green on CI)
Walk Sprint 12 savings goals in light, dark and the largest text: Wishlist › Goals (add a goal with a date, one
without, one linked to a wishlist item via the item's "Start a Savings Goal"), the Dashboard Goals card, archiving a
goal, and trying to delete an account and a wishlist item that a goal uses (both must be refused with a message).
Screenshots go under `docs/walk/sprint-12/local/`; list defects in `TO-CLOUD.md`.

## Re L-004 — the focus failure is real, not Xcode 27-only
CI (Xcode 26.6) failed `testBudgetScreensInDarkAndLargestText` the same way on 9d233cd. Fixed in 6022383: the budget
limit and goal target rows focus their field on a tap anywhere on the row. When you run L-004, use 6022383 or later;
it should pass now.

## Re L-004 / L-005 — thanks; fixed in the next push
- Every labelled text row (amounts, names, notes: transaction, transfer, recurring, Quick Add, wishlist, purchase,
  account, task, budget, goal editors) now uses a shared `FocusingRow`: a tap anywhere on the row focuses the field.
- Dashboard Recent activity rows are leading-aligned.
- Not changed yet (logged for the Sprint 16 polish pass): the clipped Category picker chevron at XXXL (a system
  Picker), and the empty Budgets state's "Add budget" under the floating +.

## L-007 — open (after the FocusingRow push is on build/v1.1)
At the largest text size, tap the label (not the field) of: Budget › New transfer › Amount, Quick Add › Amount (open
details), Wishlist › new item › Estimated price, and Tasks › new task › Title. Each must bring up the keyboard in that
field. Screenshots to `docs/walk/sprint-10/local-rewalk/`, results in `TO-CLOUD.md`.

## L-008 — open, priority (before L-006/L-007)
Sprints 12 and 13 have not compiled anywhere yet (CI keeps replacing queued runs). Pull `02eeacd` or later and run
`Scripts/verify.sh --keep-going`. Report in `TO-CLOUD.md` straight away: any compile error or swift-format lint
message verbatim (file:line), then failing tests with their messages. Don't fix code; the cloud session will.

## L-009 — open, priority
1. Pull `3c0d6cd` or later (Sprint 13 column rule, CI pinning, Sprint 14 search + reminders) and run
   `Scripts/verify.sh --keep-going`. Report compile, swift-format and test failures verbatim in `TO-CLOUD.md` as each
   step finishes (Swift 6 concurrency errors around UserNotifications are the most likely).
2. By hand on the Simulator: Settings › Reminders › turn on "Tasks due today" and allow notifications; create a task
   due tomorrow; send the app to the background. In the debugger (or a temporary breakpoint), check that
   `UNUserNotificationCenter.current().pendingNotificationRequests()` holds one `task-…` request for 9:00 tomorrow.
   Also try Budget › Transactions search with an amount (e.g. "4.50") and Wishlist search with an accent. Report.
