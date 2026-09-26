# Walk queue

Only items no automation can reach from the current environment. Each entry: sprint, numbered steps, expected
result, and why it could not be walked automatically. Emptied at the next walk on the owner's Mac.

## Pending
- **Sprint 6 (Phase 7) — backup and restore through the Files app.** On the Simulator or a device: add a few
  transactions and a wishlist item with a photo; Settings › Backup and export › Back up now; save the folder in
  Files. Delete the app's data (reinstall), finish onboarding, then Restore from backup… and pick the folder.
  Expected: a confirmation that says everything will be replaced; afterwards balances, wishlist (with photo), and
  tasks match the original. Why queued: the system document picker cannot be driven reliably by UI tests; the
  backup format, validation, and restore are covered by unit tests.

- **Sprint 7 (Phase 8) — on-device AI on a device with Apple Intelligence.** Settings › Intelligence: turn on all
  three switches. Quick Add: type "twelve dollars lunch" (amount and Dining should be suggested and labelled), then
  "47.50 coffee" (nothing from the model may override the parsed amount). Analytics › Summary › Write summary: the
  text must only quote figures shown on the screen. Also run the unit tests there with
  `TEST_RUNNER_HH_LIVE_AI=1 Scripts/test.sh`: the live AI fixtures are opt-in and need the model ready. Why
  queued: the CI simulator's model is unreliable (usually absent; once reported available and then failed every
  request, run 36211058160).
- **Launch baseline (Phase 10).** `LaunchPerformanceUITests.testLaunchPerformance` records cold-launch time in
  CI without a threshold. CI run 36216543703 measured an average of **3.197 s** (2.81–3.57 s over 5 launches) on
  the shared runner's simulator; spec §9 NFR is **under 2 s** to an interactive Dashboard on the reference device.
  On the Mac, run it in Xcode on the iPhone 17 Pro Max simulator: if it is under 2 s, set that as the baseline and
  commit it so regressions fail; if not, profile with Instruments (App Launch) — the store is opened synchronously
  in `HouseholdHubApp.init` before the first frame. Why queued: CI's shared simulator is too slow and noisy to
  judge a 2 s target.


- **Before any on-device walk: delete the app first.** SchemaV1 stays editable until the first release (recorded
  decision) and has gained fields since early sprints (AI switches, widget and Face ID settings). A store written by
  an older build may not open with the new model ("store unavailable" screen). CI always starts fresh.
- **Face ID gate (Phase 10).** Settings › Privacy › Require Face ID: turning it on asks for Face ID first; leave
  the app and come back — it must lock, the app switcher must show only the lock, and the passcode must work as a
  fallback. With the lock on, run the Log Transaction shortcut: it must ask for Face ID first (whether a background
  shortcut can show that prompt is the open question; if it can't, it refuses with "Household Hub is locked").
  Remove the device passcode: the app opens with an alert and the switch stays on. Why queued: the CI simulator has
  no passcode, so the switch is unavailable there.

## Done
- ~~Cold-launch 22 s blank screen (run 36209505191).~~ Not reproduced: the launch metric in run 36216543703 measured 2.8–3.6 s; the slow UI-test starts were simulator warm-up and automation setup. The 2 s target itself is tracked under Launch baseline.
- ~~Owner decision — Google Sheets export.~~ Dropped from v1 (owner, 2026-09-26); CSV covers it.
- ~~Sprint 0/1 (Phases 0–1) — visual pass of the tab shell.~~ Covered by the automated screenshot walks from Sprint 2
  on (every tab and More › Analytics / Settings in light, dark, and largest text; `docs/walk/`).
