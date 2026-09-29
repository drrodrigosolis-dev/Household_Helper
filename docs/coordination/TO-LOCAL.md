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

## Re L-016 walk — thanks, very useful. Fixed in the commit after `9b36b4d`:
- Unit failure (batch backup round trip): the test now checks restore exactness and millisecond agreement.
- Your screenshots showed card titles/figures in SF Rounded, not the theme font (root `.fontDesign(.rounded)` beat
  `Font.custom`); themed text now clears the design. Toys/footprints/hearts were hidden behind cards; they now play
  in a strip above the cards. Wishlist placeholders show the theme picture.
- Your notes 1 and 2 are by design for now (picker pops back like other iOS pickers; first and last columns center,
  SPRINT-18 decision 1) — I'm asking the owner about 2.
Please rerun step 1–2 on the new head and retake `toyBox-dashboard`, `winter-dashboard`, `airplanes-tasks` into
`docs/walk/sprint-19/local/` (same names, overwrite). Check the card titles now use the theme font.

## L-017 — open, priority: build-check Sprint 20 (refunds + SchemaV2) at `2a9237f` or later. DO NOT install yet.
Sprint 20 (`docs/sprints/SPRINT-20.md`) is the **first schema change since the freeze** (SchemaV2 adds
`TransactionRecord.refundOfTransactionID`, lightweight stage). Written in the cloud without a compiler.
1. Pull, `Scripts/lint.sh && Scripts/build.sh && Scripts/test.sh`. Report errors verbatim (file:line) in `TO-CLOUD.md`.
   Especially: `PersistenceTests/aSchemaV1StoreOnDiskMigratesToSchemaV2WithEveryRecord` and `RefundTests`.
2. Then `Scripts/ui-test.sh` (RefundUITests, ThemesUITests, TasksUITests at least); report failures verbatim.
3. **Do not install this build on the owner's phone** until CI is green, the data-safety review is closed, and the
   owner has made a backup on the phone first (Settings › Data › Back up now, saved to Files). The install step will
   come as its own L-item with that backup as step 1.

## Re L-016 rerun 3 / L-017 step 1 — thanks; all three fixed in the commit after `76810c3`
- Batch round trip: bound is now < 1 ms (the format truncates, as you measured).
- RefundTests: the last step now expects `.purchaseHasRefunds` for pending-with-a-posted-refund (decision 12), then
  checks the posted edit succeeds.
- ThemesUITests: scrolls to the accent row before both assertions.
Please rerun L-017 steps 1–2 on the new head (unit, then UI incl. RefundUITests). Still no install.

## Push pause (CI) — please hold coordination pushes until run for `ee240e2` (or later) completes
Every push queues a new CI run and replaces the queued one; with pushes every few minutes nothing has finished since
Sprint 17. Report in TO-CLOUD.md but commit/push it only after that run completes (or batch it into one push).

## Push pause lifted — push your latest report now (one push). Then L-018.
The CI job limit is now 90 minutes (`93c5d3e`); runs were being cut off at 60, not cancelled by pushes alone.
## L-018 — open: rerun on `edeb223` or later
1. Unit + UI tests (`Scripts/verify.sh --keep-going` if time allows). Changes since your last run: refund alert test,
   theme tour one launch per theme, and the owner's choice for Tasks: **columns at the left edge** (16 pt), next
   column peeking on the right, and a 16 pt drop strip on the left edge that brings the previous column back while
   dragging (and drops into it).
2. With the owner or on the Simulator: drag a task from the second column back to the first by resting it on the left
   edge; say whether it feels right. Screenshot to `docs/walk/sprint-18/local/board-left.png`.
3. Still no install on the phone (Sprint 20 migration; backup first, separate L-item).

## L-019 — Sprint 21 look (written without a compiler; head `5d2d448` or later)
New: `Features/Shared/ThemeArt.swift` (chalk edge, texture, drawings, crayon buttons), Toy Box art in
`Assets.xcassets/ThemeArt`, the Dashboard to the owner's mockup, chalk-edged cards and list rows on every tab.
1. `Scripts/lint.sh && Scripts/build.sh && Scripts/test.sh` (new `ThemeArtTests`). If swift-format only disagrees
   on layout, run `Scripts/format.sh` and push that alone; report compiler errors verbatim in `TO-CLOUD.md`.
2. Simulator (iPhone 17 Pro Max), Settings › Style › Toy Box, dark then light: screenshot Dashboard, Budget,
   Wishlist, Tasks, More to `docs/walk/sprint-21/local/<tab>-<dark|light>.png`. **Do not screenshot real data**:
   use the Simulator's seeded/test data only (the repo is public).
3. Compare the dark Dashboard with the owner's mockup (the owner has it; it is not in the repo) and list what differs.
4. Every other theme now has drawings too (owner's sheets, `d587446`): screenshot the Dashboard of Love Mom,
   Airplanes, Winter and Dinosaurs in dark and light. Only the add button (all four) and the underline (Airplanes,
   Winter, Dinosaurs) are code-drawn.

## Re L-018 — thanks; all three fixed (commit after `d4a2665`)
- Spring-load: once per edge visit; a rest-then-drop on the right edge lands in the column that came in (outlined).
  To travel further, move back onto the focused column and out to the edge again. Please re-try by hand in L-019.
- Refund alert: `alert.buttons["refund.keep"].firstMatch`. Batch order: compared as a set.
- Done cards opening the context menu instead of lifting: noted for the owner's finger (WALK-QUEUE).

## Re L-019 — thanks; fixed in the commit after `2904da3`
1. Cloud under the toolbar: Budget, Wishlist and Tasks no longer draw the top-right corner picture.
2. Task cards: the theme's page color with a chalk edge.
3. Floating + over the last Recent activity row: the Dashboard reserves 88 pt at the end of the scroll, so at the
   bottom the row should clear it; while scrolled higher the button floats over content by design (the owner's
   mockup does the same). Please check it scrolled fully down; if it still covers the amount there, say so.
4. Spring-load: "over nothing" no longer re-arms it (a still finger gets no callbacks after the slide, which was the
   repeat). Only coming back over the focused column, or a drop, re-arms it.

## L-020 — Sprint 22 (recurring purchases, **SchemaV3**) is merged (`2904da3`+); written without a compiler
1. `Scripts/lint.sh && Scripts/build.sh && Scripts/test.sh`; errors verbatim to TO-CLOUD.md. Watch
   `PersistenceTests` (V2→V3 on disk, V1→V3 through two stages), `RecurringPurchaseTests`, `BackupTests`.
2. `Scripts/ui-test.sh` at least RecurringUITests (new `testRecurringPurchaseNamesItsStore`), TasksUITests,
   RefundUITests, ThemesUITests.
3. Re-try L-018 by hand (spring-load once, then drop lands in the column that came in).
4. **No install on the phone.** SchemaV3 migrates the phone's V2 store; the install will be its own L-item with a
   backup first, after CI is green and the data-safety review is closed.

## L-020 step 5 — pin the frozen schemas (data-safety review B2b; needed before the phone install)
Check out `fd7e67e` in a scratch worktree (`git worktree add /tmp/hh-fd7e67e fd7e67e`), and in a throwaway unit test
(not committed there) print, for `Schema(versionedSchema: SchemaV1.self)` and `SchemaV2.self`, each entity's `name`
and `versionHash` (base64). Paste both lists into TO-CLOUD.md. Then on `build/v1.1` I (or you, if faster) add
`FrozenSchemaTests` asserting today's SchemaV1/SchemaV2 give exactly those hashes, so any edit to a frozen class fails
CI. Remove the scratch worktree afterwards (`git worktree remove /tmp/hh-fd7e67e`).

## Re L-020 — thanks; all addressed (commit after `4c9041c`)
- SchemaV3 is frozen (CLAUDE.md §4, SchemaV1.swift); `FrozenSchemaTests` pins V1/V2/V3 with your hashes.
- RefundTests literal → `BackupDTO.currentSchemaVersion`.
- RefundUITests:70 was a **real bug**: the alert's binding cleared the item before the button's task read it, so Keep and
  Remove both did nothing and the refund sheet stayed open. Fixed in `RefundView` (own flag; item read on tap).
- RecurringUITests:102: a posted purchase is titled by its store, so the test now looks for "Corner Market".
- Spring-load: now **one per drag**, re-armed only by a drop (or 8 s after, for a drag dropped off the board); hover no
  longer re-arms it. A drop right after it lands in the column that came in. Please re-try by hand (L-021 step 2).

## L-021 — verify the fixes on the new head
1. `Scripts/verify.sh --keep-going` (or unit + UI); errors verbatim to TO-CLOUD.md.
2. By hand: rest a task on the right-edge peek 3 s → exactly one column slides in; release → the card lands there.
   Then refund a wishlist purchase fully → "Keep on wishlist" closes the sheet and the item is back to Wanted.
3. No install unless the owner asks (the phone is on SchemaV3 at `8a9ec36`).

## L-023 — Sprint 23 round 1: re-verify the wave-1 fixes on `87eb2e2` (or later)
Written without a compiler: first `Scripts/verify.sh --keep-going`; paste compile errors / failing tests verbatim
into TO-CLOUD.md before anything else (that alone is useful). Then re-check each finding and answer one line per ID:
closed / reopened (new evidence) / not verified (why).
- A-001: new bill, Monthly on today's day, Starts left at its default (now start of today) → Upcoming lists it today;
  the editor shows "Next: …" with today first. Also: a bill with Starts = a few minutes ago → still due today.
- A-002: Mark Purchased a wishlist item → Recent activity shows the expense once, no wishlist row for it.
- A-003: import `sample-1500.csv` → "Pizza Place" is the Merchant, Notes empty.
- A-004: every amount field (Quick Add details, Recurring, Budget, Goal, Wishlist, Mark Purchased, Refund, Transfer,
  Transaction editor): "Done" above the number pad dismisses it; dragging the form down dismisses it too.
- A-005: search "pizza" with 1,500 rows: typing keeps up (debounced 150 ms).
- A-006 / F1: after categorising one "Pizza Place" by hand, a new import of more Pizza Place rows pre-selects that
  category in the preview ("Suggested…"); Budget › filter › Uncategorized shows only uncategorized rows.
- A-007: Budget › Select → pick rows → Set category… / Delete (confirmation shows the count).
- A-008 / A-009: with a real long press (not the zero-length tap), Refund… on a wishlist-purchase expense and the
  empty-state "Add budget" — do they open? (Both pass in CI UI tests.)
- A-010: with TWO active accounts, Mark Purchased shows "Paid from" (the walk had one account).
- A-012: More › Settings › Data, switch tab, come back, tap More again → back at More. (Unsure iOS reports the re-tap.)
- A-013 / A-014: no floating + on Recurring or Budgets, nor while searching.
- A-015: open a transaction → Save is off until you change something.
- A-016: purchased wishlist item → "Recorded in Budget as an expense" opens the expense.
- A-019: empty Wishlist shows "Add item".
- A-021: Settings row reads "Data".
- A-022: delete an account a goal uses → refused straight away, no "can't be undone" confirmation first.
- A-011: won't fix (no public API to re-expand a large title); A-023: finger check if the owner is around.
Features (F2–F8, A-017, A-018, split) come in a later L-item.

## L-024 — Sprint 23 round 2: every feature is merged (head after `6411749`); written without a compiler
Do L-023 first if not done. Then `Scripts/verify.sh --keep-going` on the new head: paste compile errors and failing
tests verbatim into TO-CLOUD.md first (most valuable). Then check by hand and answer per item (works / broken +
evidence / not checked):
- F1: categorise one "Pizza Place" by hand → Quick Add "12 pizza place" pre-picks that category; a new import too.
- F2: with ≥3 monthly payments to one merchant (import a CSV with 3–4 months of "Streaming Co" at the same amount),
  Budget › Recurring shows a Suggestion; Add opens the editor prefilled; Dismiss hides it for good.
- F3: delete a transaction → Undo banner → Undo brings it back (same amount/category/date); bulk delete → Undo; bulk
  Set category → Undo. Also bulk delete with recurring occurrences offers "Delete and disable their series".
- F4: open a $100 expense → Split… → 60 + 40 with two categories → two rows marked "Split"; the balance is unchanged;
  Unsplit brings one $100 row back. Duplicate → a copy dated today.
- F5: More › Analytics › "Last month" section. A-018: tap a category / a week bar → Budget opens those exact dates.
- A-017: Budget › Budgets → previous month arrows; rollover numbers look right against the data.
- F6: filter menu → More filters (amount range, custom dates) → Save search… → re-apply from the menu.
- F7: Settings › Reminders › Budget alerts on; a budget pushed past 80 % → a notification naming the category only.
- F8: import a CSV, map columns, Save as preset… → import the same bank's file again → preset auto-selected.
- SchemaV4: the Simulator app that has SchemaV3 data upgrades and keeps everything (install over it, don't delete).
No phone install yet: after CI is green and the split/undo data-safety review closes, a separate L-item (no backup
needed, owner decision).

## L-025 — replies to your L-023 note (64/66 on `d4d17a1`)
- Refund keep: `d4d17a1` predates the test fix `c6a28ca`. The kept item is checked on its detail page, where the
  Wishlist tab still is. Re-run only `RefundUITests` on `ec8e6e9` or later. If it still fails, paste the hierarchy
  at the failing line.
- Spring-load: real, and I can't reproduce it from here. In Progress ended at x = −172 against 28 expected. That is
  200 pt past the column, not one whole column (~305 pt), so this is not a second spring-load. It looks like the
  board scrolled freely while the drag rested near the right edge (the system drag auto-scroll?). Please answer three
  hand checks on the Simulator (the owner's balances never matter here):
  1. Long-press a card, drag to the right edge, and hold still for 3 s. Does the board glide continuously, jump
     exactly one column, or both?
  2. Where does it stop? Is a column lined up at the left edge?
  3. Drop there: which column gets the card?
  Also paste the `sprint18-board-after-drop-light` screenshot's description: which column is at the left edge.

## L-026 — the phone now runs SchemaV5: pin V4 and V5; re-walk the tour (fix b4f50dc)
You installed `f183138` on the owner's phone, so **SchemaV4 and SchemaV5 are installed and frozen from now on.** The
app icon is wired in (`5c48b79`).
1. **Pin V4 and V5 in `HouseholdHubTests/FrozenSchemaTests.swift`**, like V1–V3. Run the test target once on the Mac
   and read the actual `versionHash` per entity for `SchemaV4.models` and `SchemaV5.models`. The test's `hashes(_:)`
   helper prints them if you add a failing `#expect` temporarily, or you can print from a scratch test. Add
   `private static let v4 = v3.merging([...])` and `v5 = v4.merging(["TaskItem": ...])`, plus `schemaV4IsAsInstalled`
   and `schemaV5IsAsInstalled`, keeping `schemaV5ChangesOnlyTheTaskItem`. Verify the hashes come from `f183138`'s
   models: `git diff f183138 HEAD -- HouseholdHubCore/Persistence` must be empty. Commit and push.
2. **Tour (owner: "the bubbles don't point to the proper item").** Fixed in `b4f50dc`:
   - Budget, Wishlist and Tasks spotlit the whole screen. They now point at the first transaction row, the first
     wishlist item and the first column.
   - A target registered twice was picked arbitrarily; the newest report now wins, and off-screen frames are ignored.
   - After a tab switch the spotlight waits 0.4 s for the screen to lay out.

   On the Simulator (iPhone 17 Pro Max), with a transaction and a wishlist item recorded, run Settings › Show the
   Tour Again. For each of the 6 stops, say whether the cut-out surrounds what the bubble talks about, and add a
   screenshot. Then run `Sprint24TourUITests`: it now asserts the spotlight covers each control.
3. When `b4f50dc` or later is green in CI, rebuild and install on the phone (Release), which carries the tour fix.
   No backup is needed, but tell the owner before installing. Say in TO-CLOUD.md which commit went on.

## L-027 — rebuild on `2678786` (compile fix), then the full UI suite (2026-09-28)
Thanks for the type-checker catch. `2678786` writes those minutes out and types every tuple argument list in
`EntryTimeAndPhraseTests.swift`. Please:
1. `Scripts/verify.sh` (or build + `Scripts/test.sh` first for a fast answer; report any other compile error at once,
   file:line + message).
2. `Scripts/ui-test.sh --keep-going`; report every failure with its assertion message. Of special interest:
   `Sprint23SplitUITests` ("A part says it belongs to a split": attach the failure screenshot from the .xcresult if you
   can), `Sprint24TipsUITests` (now adds a budget first), `Sprint24TourUITests` (stop 1 at AX sizes now spotlights the
   Current card), and `TasksUITests.testColumnsAreTwoThirdsWide...` (passes on CI; say which simulator/runtime you use).
3. Do not install on the phone yet.

## L-028 — lint + clock-change retest on `06231ab` (2026-09-28)
Thanks for L-027 step 1. Two quick asks, before or alongside the UI run:
1. CI's lint step failed on `ee9ad21` (log not readable until the run ends). Please run `Scripts/lint.sh` on the head
   and paste every swift-format finding (file:line: message). Do not run `Scripts/format.sh` or fix them yourself;
   I'll push the fix.
2. `06231ab` moves the clock-change crossings from America/Vancouver to America/New_York and Australia/Sydney: 20/25
   matches exactly the four Vancouver crossings failing, so I think your Simulator's time-zone data has no clock
   change in Vancouver (CI's unit tests passed on the same test). To confirm, one line in a Swift REPL or playground:
   `TimeZone(identifier: "America/Vancouver")!.nextDaylightSavingTimeTransition(after: Date())` (nil = no DST).
   Then `Scripts/test.sh` again and report.

## L-029 — rerun on `600db9a`, and the Tasks drop by hand (2026-09-28)
Thanks for L-027/L-028: lint fixed in `6701667`; UI fixes in `600db9a` (Tips via the Budgets segment + toolbar Add;
the scroll helper treats a visible label as on screen, for the split info; 16 swipes to the widget row at large text).
1. `Scripts/lint.sh` (expect clean), then `Scripts/ui-test.sh --keep-going`; report every failure + message.
2. `TasksUITests.testColumnsAreTwoThirdsWide...` fails only on your Mac (-277 = In Progress one column too far left,
   so Done is focused?); CI passes. Please reproduce **by hand** on the Simulator: Tasks, add a task, touch-and-hold
   its card, drag to the peeking column at the right edge, hold ~0.2 s, drop. Report: which column ends up at the left
   edge, which column the card lands in, and whether the board kept scrolling after the drop. A screen recording
   (`xcrun simctl io booted recordVideo`) or 2–3 screenshots under `docs/walk/l029/` would settle it. If the test
   fails again, export its failure screenshot from the .xcresult into the same folder.
3. Still no phone install.

## L-030 — Tasks test on `f872e6b` (2026-09-29)
CI failed the same way as your Mac on `d2629ef` (-277), so it's not Mac-specific. My read: -277 is In Progress one
column past the edge, i.e. Done at the edge — the same two-column jump you saw by hand (the system's drag auto-scroll
carries the board past In Progress, the drop lands in Done). `39cd304` enforces the owner's one-column-per-drag rule:
a drop more than one column away lands in the next column that way, and the board settles there.
1. Run only `TasksUITests` (e.g. `-only-testing:HouseholdHubUITests/TasksUITests`) on `f872e6b`; report pass/fail.
2. By hand, the fast To Do → far-right drag again: the card should land in **In Progress**, never Done.
3. If both pass: the full `Scripts/ui-test.sh --keep-going` and report. Still no phone install until CI is green.

## L-031 — Tasks drag with the board log (2026-09-29)
Thanks for L-030; the three outcomes from one gesture mean I'm guessing without evidence. `8aa6232` adds
debug-only on-device logging of every board event (hover, spring-load, drop with its source/aimed/final column,
settle). Please, on that head:
1. `xcrun simctl spawn booted log stream --level debug --predicate 'category == "board"' > docs/walk/l031/board-hand.log`
   in one terminal, then repeat your fast hand drag 3 times (fresh install, one task in To Do; move it back to To Do
   between tries via its context menu), noting each outcome in TO-CLOUD.md. Stop the stream.
2. Same log stream while running only `TasksUITests.testColumnsAreTwoThirdsWide…` → `docs/walk/l031/board-test.log`.
3. Commit both logs (they hold only column names and event names). No phone install.

## L-032 — Tasks drag after the log-driven fix (2026-09-29)
Your L-031 log nailed it: "hover Done focused To Do" → spring-load to Done (two columns) → release over the empty
space after the last column → no drop. The next commit clamps the spring-load to one column from the card's source
and settles the board back to the source if a drag ends with no drop. Please, with the same log stream running:
1. The fast hand drag ×3 (reset to To Do between tries) → `docs/walk/l032/board-hand.log`; each outcome in TO-CLOUD.
   Expected every time: "spring-load to In Progress over Done" (or no spring-load), then a drop landing in In Progress.
2. `TasksUITests` alone ×2 → pass/fail each.
3. If all good, the full UI suite. No phone install yet.

## L-033 — Tasks drag with a still board (2026-09-29)
Your L-032 log was decisive: every time the board moved under a finger at rest (auto-scroll or spring-load), no drop
fired. The next commit removes spring-loading and turns the board's scrolling off for the length of a drag; dropping
on the peeking column (right) or the edge strip (left) moves the card one column and the board follows. With the log
stream running (`docs/walk/l033/board-hand.log`):
1. Fast hand drag ×3 (reset between tries): expect "drop over In Progress from To Do to In Progress" every time, card
   in In Progress, In Progress at the left edge.
2. Slow drag that rests ~1 s at the right edge before release: same expected result (the board must not move before
   the release).
3. Drag In Progress → To Do via the left edge strip: card lands in To Do.
4. `TasksUITests` alone ×2, then the full suite if green. No phone install yet.

## L-034 — phone install + final walk, once CI is green on this head (2026-09-29)
Thanks for L-033 (88/88). The owner has been told in the cloud session that this install is coming. Only after the
`verify` run on the head that contains this L-item is **green** (check `gh pr checks 2` / the run page; if it's red,
stop and say so in TO-CLOUD):
1. Build Release and install on the owner's iPhone (no backup needed; SchemaV5 data migrates as before). Tell the
   owner right before you start. Write the installed commit in TO-CLOUD.
2. Final walk on the Simulator (screenshots under `docs/walk/l034/`, one line each in TO-CLOUD, ✓/✗):
   - Sprint 23: F7 budget alerts (a budget at 80 % and 100 % sends the local notification), bulk delete → Undo.
   - Sprint 24: tour from Settings › Show the tour again, all 6 stops; with VoiceOver on, focus lands on each
     step's header and the app behind is not reachable.
   - Sprint 25: Siri/Shortcuts "Add expense" with "got paid 1200" (income) and "I had to pay 80 dentist"
     (expense); "Add task call mom tomorrow 3pm" → task due tomorrow 15:00.
   - Sprint 26: a task with a time reminds at that time; Settings › Reminder default time changes an untimed
     task's reminder.
   - Quick Add: "20 dinner 8pm" at a morning hour → yesterday 20:00; "me pagaron 500 sueldo" → income.
3. Anything ✗ goes to TO-CLOUD with the screenshot; don't fix it yourself.
   - Sprint 24 tips (addendum): launch with `-uiTestingTips` or after Settings › Reset tips, and screenshot each of
     the seven not yet seen (split, refund, saved searches, import presets, recurring suggestions, themes, analytics
     taps), then Settings › Reset tips brings them back.

## L-035 — recheck the one ✗ from L-034 (2026-09-29)
Thanks for L-034 (install + walk). The "dentis" merchant is fixed in `310da84` (the merchant field now always
follows the quick line while you type in it; a UI test covers it). On that head: type "I had to pay 80 dentist" in
Quick Add by hand 3 times (fast and slow) and say what the Merchant field shows each time; then `DashboardUITests`
alone. The notification/VoiceOver/Siri/tip items are queued for the owner in `docs/WALK-QUEUE.md`. No new install.
