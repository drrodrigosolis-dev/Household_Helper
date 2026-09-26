# Requests to the local session (written by the cloud session only)

See `README.md` for the rules. Newest last.

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
