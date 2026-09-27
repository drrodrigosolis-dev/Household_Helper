# Requests to the local session (written by the cloud session only)

See `README.md` for the rules. Newest last.

> **Resume here (2026-09-27 evening): install on the owner's iPhone (L-013), then the device checks (L-014).**
> CI is green on `bc5ceaa` (run 36334223494); everything older (L-001…L-012) is done. Short reports in `TO-CLOUD.md`.

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

## L-010 — open (Sprint 16, after L-009 step 1)
The String Catalogs were written by hand from the source. Check them against Xcode's own extraction:
`xcodebuild -exportLocalizations -project HouseholdHub.xcodeproj -localizationPath build/l10n -exportLanguage es`
(after `Scripts/generate.sh`). In `build/l10n/es.xcloc/Localized Contents/es.xliff`, list every `<trans-unit>` that
has no `<target>` (untranslated), with its `id`, in `TO-CLOUD.md` (just the ids, one per line). Don't edit the catalogs;
the cloud session adds the missing ones. Then run the app with the Simulator set to Español and glance at Inicio,
Presupuesto and Configuración for English left over.

## Re L-009 / L-010 — thanks
The 12 untranslated ids are covered in the next push (the "(%lld archived)" key, "income"/"expense", the
format-only strings, CFBundleName). The widget and Core CFBundleName entries are left: the name doesn't change by
language. The Simulator wedge needs the owner to restart the Mac; until then skip anything that launches the
Simulator, CI covers tests. After the restart: L-010's Simulator glance, L-007, L-006, L-009 step 2.

## Re L-010 — likely a stale store, please re-check once (after L-007)
Seeding runs once per store and is English on purpose under `-uiTesting` (in-memory store, CI names). Your Inicio
shot has no onboarding, so the store was not fresh. Re-check: `xcrun simctl erase "iPhone 17 Pro Max"`, set the
device language to Español in the Simulator's Settings (no `-uiTesting*` launch arguments), install, go through
onboarding, then look at Presupuesto's category filter, Configuración › Hogar footer and Tareas. Expected:
Supermercado…, "Cuenta principal", "Por hacer / En curso / Hecho". If any is still English, report the launch
arguments you used and the device's language list (Settings › General › Language & Region).

## Re L-006 / L-009 / L-010 — thanks, all passing
Fixed in the next push: goal subtitle at XXXL puts the account on its own line (no leading "·"); the Delete rows in
wishlist item and task detail have a red icon. Kept: wishlist items in Recent activity (intended, v1 audit: the row
says the priority and opens Wishlist); Accounts rows without tap (consistent). Logged for later: account delete could
refuse before its confirmation (#1), the refusal popover anchor (#4). Placeholder "0.00" stays: the decimal mark
follows the region (es_CA uses "."), and amount parsing accepts both.

## L-011 — open (small experiment, after verify.sh)
The lost first tap on a Toggle while the keyboard is up (task editor "Fecha de vencimiento", goal editor "Target
date") — both toggles sit just below a `FocusingRow`. Please find which it is, without committing code:
1. In the goal editor, focus Target, then tap the Target date toggle once. Swallowed? (baseline)
2. Focus Name (a plain field if it isn't a FocusingRow; else say so), tap the toggle once. Swallowed?
3. Temporarily comment out `.onTapGesture { isFocused = true }` in `Features/Shared/FocusingRow.swift`, rebuild,
   repeat step 1. Revert the file afterwards.
Report the three results in `TO-CLOUD.md`. That tells me whether FocusingRow's gesture or iOS's own keyboard
dismissal eats the tap.

## Re L-011 — thanks; no change
Zero-duration synthetic taps; retracted. FocusingRow stays as is.

## L-012 — open (WALK-QUEUE Sprint 6: backup and restore through Files, on the Simulator)
Build `6b09736` or later, fresh install, English. Add two transactions and a wishlist item with a photo (drag any
image into the Simulator's Photos first). Settings › Backup and export › Back up now; save the folder in Files (On My
iPhone). Uninstall Household Hub only (not the device: it holds PersonalOS data), reinstall, finish onboarding, then
Restore from backup… and pick that folder. Expected: a confirmation saying everything will be replaced; afterwards
Current balance, the two transactions, and the wishlist item with its photo match. Screenshots to
`docs/walk/sprint-6/local/`, result in `TO-CLOUD.md`. If the document picker can't be driven with your tools, say so
and stop; it moves to the owner's device list.

## Re L-012 — thanks, fixed in the next push; please rerun L-012 end to end
Your diagnosis was right: each `fileExporter` now sits on its own section (Backup, Export). Pull the commit after
this note, rebuild, and run L-012 from the start (back up, uninstall the app only, reinstall, onboard, restore). Also
check that Export transactions as CSV still opens its save sheet. The "Data" title vs "Backup and export" row is
logged, not changed (the spec names the screen Data).

## L-013 — open, now: install on the owner's iPhone (connected to the Mac)
1. Pull `build/v1.1` (includes `Scripts/install-device.sh`).
2. On the iPhone, once: Settings › Privacy & Security › Developer Mode › On (it restarts). If an older Household Hub
   build is installed, delete it first (older SchemaV1 stores may not open; WALK-QUEUE note).
3. Xcode › Settings › Accounts: the owner's Apple ID must be signed in; note the Personal Team's Team ID. Don't commit
   it anywhere (not project.yml, not settings, not docs).
4. `xcrun devicectl list devices` for the iPhone's name, then
   `HH_TEAM=<Team ID> Scripts/install-device.sh "<iPhone name>"`.
   If Xcode reports the bundle ID is unavailable, rerun with `HH_BUNDLE_PREFIX=<something unique, e.g. com.<name>.hh>`.
5. First launch: the owner trusts the developer on the iPhone (Settings › General › VPN & Device Management ›
   Apple Development › Trust), then opens the app and onboards.
6. Report in `TO-CLOUD.md`: the installed commit (the script prints it), the bundle prefix used, and any signing or
   install error verbatim. Known: under the free team the widget shows sample figures (no App Group, by design).

**SchemaV1 freezes with this install** (CLAUDE.md §4, owner decision). The cloud session records the frozen commit in
PROGRESS from your report; from then on every stored-model change needs SchemaV2 plus a migration stage.
Free provisioning expires after 7 days: rerun the same command to reinstall; data stays on the phone.

## L-014 — open, after L-013, with the owner holding the phone (WALK-QUEUE device checks)
Guide the owner through these and write what they report; don't guess results.
1. **Face ID:** Settings › Privacy › Require Face ID on (asks for Face ID first). Leave the app, come back: locked;
   the app switcher shows only the lock; the passcode works as a fallback. With the lock on, run the Log Transaction
   shortcut: it asks for Face ID, or refuses with "Household Hub is locked" (either is acceptable; record which).
2. **On-device AI** (only if the iPhone supports Apple Intelligence): Settings › Intelligence, all three switches on.
   Quick Add "twelve dollars lunch" → amount 12 and Dining suggested and labelled; "47.50 coffee" → the amount stays
   47.50. Analytics › Summary › Write summary quotes only figures on screen. If the phone lacks Apple Intelligence,
   record "not supported" (the switches must then be unavailable, not broken).
3. **Launch time:** force-quit, then open from the Home Screen three times; for a number, Xcode › Open Developer Tool ›
   Instruments › App Launch on the device. Target under 2 s to an interactive Dashboard.

## Re "Local status — installing on the owner's iPhone" — thanks, same plan
If your Debug install is already on the phone, keep going with it for L-014 steps 1–2; for step 3 (launch time)
reinstall with `Scripts/install-device.sh` (Release, same bundle ID, data kept). Report the installed commit either way
so PROGRESS can record where SchemaV1 froze.

## Re L-013 — thanks. The Team ID line can stay (it's visible in every app it signs).

## L-015 — open, priority: build-check Sprint 17 (batch add), then install it once CI is green
Sprint 17 adds "Add several" (Tasks and Wishlist toolbars; `docs/sprints/SPRINT-17.md`), `17d1dc0`. It was written in
the cloud without a compiler.
1. Pull, then `Scripts/verify.sh --keep-going` (or at least `Scripts/lint.sh && Scripts/build.sh && Scripts/test.sh`).
   Report compile errors and swift-format messages verbatim (file:line) in `TO-CLOUD.md` as soon as you see them;
   don't fix code, the cloud session will.
2. When CI is green on the head that contains Sprint 17, reinstall on the owner's iPhone with
   `Scripts/install-device.sh` (Release; data kept) so the owner can load their tasks and wishlist items.
3. With the owner: Tasks › Add several (the list-with-plus icon), paste a few lines from Notes (a date word like
   "friday" becomes the due date), check the preview, Add. Same on Wishlist ("250 new bike"). Report what they see.

## Re L-015 step 1 — thanks. Please repeat step 1 on `67b86d4` or later (review fixes: Quick Add type switch,
double-save guard, weekday words, ticked lines; new tests in `BatchAddTests` and `BatchAddUITests`), same report.

## L-016 — open, priority over L-015 step 3: build-check Sprints 18 and 19 at `9965d1b` or later
Written in the cloud without a compiler; CI is queued behind a long run, so your compiler is the fastest feedback.
- Sprint 18 (`docs/sprints/SPRINT-18.md`): Tasks columns 2/3 wide, focus follows a moved task, spring-loaded drag.
- Sprint 19 (`docs/sprints/SPRINT-19.md`): fun themes. New `HouseholdHubCore/Domain/FunTheme.swift`,
  `HouseholdHubApp/Features/Shared/ThemeStyle.swift`, `ThemeAnimations.swift`; Settings › Appearance › Style.
1. Pull, `Scripts/lint.sh && Scripts/build.sh && Scripts/test.sh`. Report compile errors and swift-format messages
   verbatim (file:line) in `TO-CLOUD.md` as soon as you see them; don't fix code, the cloud session will.
2. If it builds: `Scripts/ui-test.sh` limited to `TasksUITests` and `ThemesUITests` if the script allows, else all;
   report failures verbatim.
3. Only with the owner free, on the Simulator: Settings › Appearance › Style › Toy Box, then Dashboard; drag a task on
   Tasks to the peeking next column. Say what looks wrong (fonts, colors, animation); screenshots welcome in
   `docs/walk/sprint-19/` (PNG, small).

## Re L-016 step 1 — thanks, both fixed in the commit after `68b6733`
Wrapped the two `isTargeted:` closures; `themes` in ThemeWordingTests is `nonisolated static let`. Please rerun step 1
on the new head, then step 2 (TasksUITests, ThemesUITests, plus BudgetUITests and RecurringUITests: CI run
36342742016 lost a swipe and a Save tap there; the tests now confirm each gesture landed). Same report format.
