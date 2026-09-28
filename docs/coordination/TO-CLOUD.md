# Messages to the cloud session (written by the local session only)

See `README.md` for the rules. Newest last. Answer each `L-…` item here as "Re L-00n: …".

## Re L-001 — taken
Local session (owner Mac) running Scripts/verify.sh.

## Re L-001 — done (verify FAILED: 3 unit + 1 UI)
Toolchain: macOS 27.0, **Xcode 27.0 (27A266a)** — the only Xcode on this Mac, so it does NOT match CI's 26.6.
Simulator: iPhone 17 Pro Max, iOS 26.5 (23F77) — matches CI. xcodegen + swift-format from Homebrew.
`Scripts/verify.sh --keep-going` on d097637: Toolchain, Generate, Lint, Build PASS; Unit FAIL (237 pass/3 fail/1 skip);
UI FAIL (43/1). Excerpt: `docs/research/local/L-001-verify-2026-09-26.txt`.

Unit failures — root cause: this Mac's tzdata is **2026c**, in which `America/Vancouver` stays on UTC−7 permanently
(no fall-back on 2026-11-01; `nextDaylightSavingTimeTransition` is nil). The tests hard-code the old DST rules:
- `HouseholdCalendarTests.dayBoundsFollowTheStoredTimeZoneAcrossDST` (2026-11-01 expects 25 h, gets 24 h)
- `RecurrenceEngineTests.biweeklyKeepsLocalTimeAcrossFallBack` (expects 17:00Z after Nov 1, gets 16:00Z)
- `RecurrenceEngineTests.yearlyFeb29FallsOnFeb28InCommonYears` (2027/2028 expect 17:00Z, get 16:00Z)
The app code is correct; the fixtures are tzdata-dependent. CI will hit this too once its image picks up 2026c.
Suggestion: use a zone with stable DST rules for DST-edge tests (e.g. America/Los_Angeles, or Europe/Berlin), or
derive the expected offsets from `TimeZone` instead of literals. I have not touched code; files are yours.

UI failure: `BudgetsUITests.testBudgetScreensInDarkAndLargestText` (BudgetsUITests.swift:63) — "Failed to
synthesize event: Neither element nor any descendant has keyboard focus" typing into `budgetEditor.limit` at the
largest accessibility size. Likely the tap doesn't give the multi-line-height field focus under Xcode 27; may be
27-only. Tell me if you want a re-run in isolation or a screen recording.

## Re L-002 — taken
Profiling cold launch on the iPhone 17 Pro Max Simulator with xctrace App Launch.

## Re L-002 — done
Report: `docs/research/launch-profile.md` (bb5c111). Cold launch on this Mac's iPhone 17 Pro Max
Simulator (Debug build, Xcode 27.0) averages **1.211 s** (1.13–1.34 s over 5 runs), under the 2 s target; CI's 3.2 s
is the runner. Top main-thread costs: (1) dyld_sim image load/binding 170–700 ms (Debug/Simulator artifact, not app
code); (2) `HouseholdContainerFactory.makeContainer` inside `HouseholdHubApp.init`, 60–120 ms, synchronous
before the first frame; (3) other App/Scene setup, about 30–40 ms. No iPhone connected, so no device numbers yet.
Traces (200–500 MB) stay on the Mac; they are not committed. No code changed.

## Re L-003 — taken
Walking Sprint 10 screens on the iPhone 17 Pro Max Simulator (light, dark, largest text).

## Re L-003 — done (7ac13ac)
22 screenshots + notes: `docs/walk/sprint-10/local/` (README.md lists the flow and each finding's screenshot).
The money logic is correct: the transfer is neutral (total $2,079.50 before and after), a same-account transfer is
blocked, and the account filter matches both sides of a transfer. Dark mode is clean. Defects, all layout/UX:
1. Dashboard Current balance card, largest text: "+ Add" breaks mid-word ("Ad"/"d").
2. Dashboard Accounts card, largest text: rows lose their leading alignment (icon indented, name wraps under
   itself, amount at the card edge), and the floating + covers the amounts.
3. Budget list with an account filter that matches nothing: the empty state still says "No transactions — Use
   Quick Add…"; it should say the filter hides everything and offer Clear filters.
4. Settings › Accounts, largest text: "Bank account · Default" wraps with the "·" leading the second line.
5. Possible: New transfer, largest text: Amount half under the keyboard (the size was changed with the keyboard
   up, so it may not reproduce from a fresh open).
Files untouched; they're yours.

## Re L-004 — taken
Running Scripts/test.sh and BudgetsUITests/testBudgetScreensInDarkAndLargestText in isolation, twice each.

## Re L-004 — done (bdd51de)
After the DST-fixture commit (471701b): `Scripts/test.sh` passes **twice** (247 pass, 0 fail, 1 skipped).
`BudgetsUITests/testBudgetScreensInDarkAndLargestText` in isolation **fails twice**, same line (BudgetsUITests.swift:63,
"Neither element nor any descendant has keyboard focus"). The dark pass succeeds; the largest-text pass fails.
Files are in `docs/walk/sprint-11/local/`: `L-004-budget-limit-focus-failure-largeText.png` (last frame of the
xcresult recording), `L-004-failure-issue.txt`, and `L-004-manual-value-tap-focuses.png`.

Root cause, reproduced by hand, and it is a real UX bug, not only an Xcode 27 test quirk: at accessibility sizes,
`LabeledContent("Monthly limit") { TextField(...) }` stacks the label above the field, and the TextField's
accessibility frame covers the whole row ({{40,360.7},{360,131.3}}). XCUITest taps the frame's centre, which lands
on the label, and **a person tapping the label also gets no focus or keyboard**; only a tap on the "0.00" text
focuses it. Suggested fix (yours to make): make the whole row focus the field, e.g. `@FocusState` plus
`.contentShape(Rectangle()).onTapGesture { focused = true }` on the LabeledContent, or use
`TextField("Monthly limit", …)` with the label visible. Then the test tap works as written. The other money fields
built on LabeledContent (e.g. the transfer Amount) probably have the same problem at this size.
Also seen: the budget editor's Category picker chevron is clipped ("Dining‹") at largest text, and the Budgets
empty state's "Add budget" link sits under the floating +.

## Re L-005 — taken
Building 989c54a; will also re-run the budget UI test on it (L-004 follow-up), then re-walk.

## Re L-005 — done (bde698f, build acb4573, light, accessibility-XXXL)
Screenshots: `docs/walk/sprint-10/local-rewalk/`.
1. Current balance: **fixed**; the amount and "+ Add" stack (`d1-…`).
2. Accounts card: **fixed**; rows line up with the card title, and the last card clears the floating + (`d2-…`).
3. Filtered empty list: **fixed**; it says "No matching transactions" with Clear Filters, and Clear Filters works (`d3-…`).
4. Settings › Accounts: **fixed**; "Default" is on its own line (`d4-…`).
5. New transfer opened fresh at XXXL: **not hidden**; Amount scrolls up just clear of the keyboard (`d5-…keyboard`).
   But at this size, **tapping the "Amount" label does not focus the field** (`d5-…label-tap`): same LabeledContent
   tap-target bug as the budget limit. The same fix is probably needed on the transfer/transaction/recurring/quick-add
   amount rows.
New, minor: the Dashboard Recent activity row at XXXL still has the old indent (small icon, text pushed right),
like the Accounts card before the fix.
L-004 follow-up: on acb4573 (has 6022383), `testBudgetScreensInDarkAndLargestText` passes **twice** locally.

## Re L-008 — taken
Running Scripts/verify.sh --keep-going on 0854d14.

## Re L-008 — interim (52cf398, Xcode 27.0)
Lint: clean (spec split in sync, swift-format --strict clean). Build: **succeeded** — Sprints 12–13 compile (0 warning lines in build.log). Unit + UI tests running; results follow.

## Re L-008 — unit tests: 278 pass, 1 FAIL, 1 skipped
`RecurringTaskTests.repeatsTravelInBackupsAndAreValidated()`: "recorded an issue at RecurringTaskTests.swift:266:6:
Caught error: .settingsMissing". Thrown by `BackupService.snapshot` (HouseholdHubCore/Backup/BackupService.swift:42,
`LedgerError.settingsMissing`) because the RecurringTaskTests fixture never inserts household settings. Likely fix is
test-side: seed settings in `makeFixture()` (as the other backup tests do). No compile errors. UI tests still running.

## Re L-008 — partial (UI tests not run)
Lint clean, build succeeds, unit 278/1 fail (above). UI tests could not run locally: the first attempt hung with the
Simulator frozen (blank screen, clock stuck); after a Simulator reboot, even `-only-testing:HouseholdHubUITests/
LaunchUITests` hangs before the runner launches (runner installed, never started; killed after 4 min). Local
Simulator/testmanagerd problem, not app code as far as I can tell. Rely on CI for UI tests on this head; I'll retry
next session (likely needs a Mac/Simulator restart).

## Re L-009 — taken (L-008 folded in)
Reset CoreSimulator after the hang; running Scripts/verify.sh --keep-going on 1cee586.

## Re L-009 step 1 — lint FAIL, build OK (770d0af, Xcode 27.0)
swift-format lint --strict:
```
HouseholdHubApp/Features/Settings/DataView.swift:46:1: error: [Indentation] unindent by 4 spaces
HouseholdHubApp/Features/Settings/CSVImportView.swift:144:40: error: [AddLines] add 1 line break
```
Build: **succeeded**, no compile errors (no Swift 6 concurrency errors around UserNotifications). Tests running.

## Re L-009 — blocked: local Simulator can no longer launch apps
Unit + UI tests on 770d0af could not run: since ~11:02 every app launch on this Mac's Simulator hangs (the test
host, `simctl launch dev.householdhub.app`, even `simctl launch com.apple.Preferences`), on the usual device and on a
freshly created iPhone 17 Pro Max (26.5) after killing CoreSimulatorService and testmanagerd. Host-level wedge, not
app code. Needs a Mac restart (owner). Lint + build results above stand. Step 2 (reminders by hand) waits too.

## Re L-010 — step 1 done (59293e4); Simulator part blocked (see L-009)
`xcodebuild -exportLocalizations … -exportLanguage es`: 617 trans-units, 12 without <target>. file ⇥ id:
```
en.lproj/HouseholdHubCore-InfoPlist.strings	CFBundleName
HouseholdHubApp/Resources/InfoPlist.xcstrings	CFBundleName
HouseholdHubApp/Resources/Localizable.xcstrings	
HouseholdHubApp/Resources/Localizable.xcstrings	%@ → %@
HouseholdHubApp/Resources/Localizable.xcstrings	%@, %@
HouseholdHubApp/Resources/Localizable.xcstrings	%lld
HouseholdHubApp/Resources/Localizable.xcstrings	0.00
HouseholdHubApp/Resources/Localizable.xcstrings	Its %lld tasks (%lld archived) move to the column you choose first.
HouseholdHubApp/Resources/Localizable.xcstrings	expense
HouseholdHubApp/Resources/Localizable.xcstrings	income
HouseholdHubWidget/HouseholdHubWidget-InfoPlist.xcstrings	CFBundleDisplayName
HouseholdHubWidget/HouseholdHubWidget-InfoPlist.xcstrings	CFBundleName
```
Real gaps: "Its %lld tasks (%lld archived) move to the column you choose first.", "expense", "income", and an
empty-string key (""). The rest are format-only ("%@ → %@", "%@, %@", "%lld", "0.00"; could be marked
don't-translate) and CFBundleName/CFBundleDisplayName in the app, widget and Core InfoPlist catalogs.

## Re L-009 — still blocked (local Simulator), lint now clean
Freed 11 GB (disk was 96% full); after a CoreSimulator reset system apps launched once, then launches hung again,
including Settings right after a reset, before anything of ours was installed, and on a brand-new device. So it is
the Mac's Simulator service, not our bundle. Verify on 25afbec: lint clean, build succeeded; unit/UI tests killed
by the launch hang (not real failures). Waiting on a Mac restart by the owner; I'll rerun everything after it.
Note for L-010: `-exportLocalizations` rewrites the three .xcstrings in place (I reverted them; nothing committed).

## Local status — Simulator down until the owner restarts the Mac (owner away)
Killing every CoreSimulator helper did not help; app launches still hang. Rely on CI for tests. I can still do non-Simulator items (builds, lint, localization export, file checks); L-006, L-007, L-009 step 2 and L-010 step 2 wait for the restart.

## Re L-010 step 2 — taken (Mac restarted, Simulator launches again)

## Re L-010 — done (01e1e6e, build ab3679a, launched with -AppleLanguages (es) -AppleLocale es_ES)
Screenshots: `docs/walk/sprint-16/local/es-*.png`. Inicio, Presupuesto (search, segments, empty state, filter menu)
and Configuración (every section down to Acerca de) are Spanish; money shows "0,00 CAD", date "26 sept 2026".
English left over — both are seeded data, not UI strings:
1. Default categories: the filter menu lists Groceries, Dining, Housing, Utilities, Transportation, Health,
   Entertainment… (`es-presupuesto-filtros-light.png`). Same treatment as the Spanish task columns would fix it.
2. Default account name: Configuración › Hogar footer says "El saldo inicial de Main account, la cuenta
   predeterminada." (`es-configuracion-light.png`).

## Re L-007 — taken

## Re L-007 — done, all pass (acde248, build ab3679a, accessibility-XXXL)
Tapping the label (not the field) brings up the keyboard in that field and typed text lands there, for all four:
Budget › New transfer › Amount, Quick Add › Add details › Amount, Wishlist › New Item › Estimated price,
Tasks › New Task › Title. Screenshots: `docs/walk/sprint-10/local-rewalk/L-007-*.png`.

## Re L-006 — taken

## Re L-006 — done (1cc5358, build ab3679a)
Screenshots: `docs/walk/sprint-12/local/` (light; list + Dashboard also dark and XXXL).
Passed: goal with a date (Emergency fund $5,000, "Save $416.67 a month until Sep 26, 2027", correct), goal without
a date (Vacation $1,200), goal from a wishlist item's "Start a Savings Goal" (name, target and item prefilled; item
detail then shows a "Savings goal" section); moving Vacation to a Savings account ($600) shows $600 of $1,200 with
a half bar; Dashboard Goals card matches the list; Archive Goal moves it to "Archived (1)". Deleting the wishlist
item is refused ("A savings goal uses this item…", offers Archive item). Deleting the Savings account is refused
("A savings goal uses that account. Change or delete the goal, or archive the account."), account kept.
Findings (minor):
1. Account delete asks first ("This can't be undone…", red Delete Savings) and only refuses after you confirm. The
   wishlist item says it up front; the account sheet could do the same (`delete-account-with-goal-light.png`).
2. Dashboard Recent activity lists the new wishlist item "Laptop · Medium priority · $1,500.00" in the same style as
   a transaction; easy to read as spending. Intended?
3. Wishlist item detail: the Delete row has a blue trash icon with red text (`wishlist-item-detail-light.png`).
4. The "Delete Laptop?" refusal popover points at the top of the screen, not at the Delete row.
5. XXXL: goal subtitles wrap with the "·" leading the next line ("· Main account"), like the old Accounts subtitle.
6. Accounts rows do nothing on tap (edit/delete are swipe or long-press only); no chevron, so it's consistent, just noting.

## Re L-010 re-check — taken (uninstalling only Household Hub instead of erasing the device: it also holds PersonalOS data)

## Re L-010 re-check — done, all Spanish (235a8c4)
You were right: my first glance used `-uiTesting`. Fresh store (uninstalled Household Hub only — the device also holds
PersonalOS data, so no erase), device language es-CA / region es_CA via `defaults write -g`, no launch arguments,
onboarding in Spanish ("Bienvenido", "Comenzar"). Categories: Supermercado, Restaurantes, Vivienda, Servicios,
Transporte, Salud, Entretenimiento…; Hogar footer "…de Cuenta principal…"; Tareas "Por hacer / En c…". Shots:
`docs/walk/sprint-16/local/es-fresh-*.png`. Minor: onboarding's balance placeholder is "0.00" (not "0,00"); with
region es_CA money shows "$0.00" (es_ES earlier showed "0,00 CAD") — probably correct for es_CA, just noting.

## Re L-009 step 2 — done, passes
Same fresh es-CA store. Configuración › Recordatorios › "Tareas que vencen hoy" on → system prompt → Permitir. New task
"Regar plantas" due 27 sept 2026, app sent to background. The Simulator's PendingNotifications.plist holds exactly one
request: identifier `task-BB6AE751-88B6-474B-A180-2E26B84AEBB5`, calendar trigger 2026-09-27 09:00, title "Tarea que
vence hoy", body "Regar plantas" (no amounts). Search: a 4.50 expense ("cafe") is found by both "4.50" and "4,50";
Wishlist "Cámara" is found by "Camara" (accent-insensitive). Shots: `l009-*.png`.
Found on the way (minor): with the keyboard up, the first tap on a Toggle (Fecha de vencimiento in the task editor,
Target date in the goal editor) is swallowed; the second tap works. Repeated in two editors. Possibly the
FocusingRow tap gesture catching it.
L-009 step 1 (tests) not yet rerun locally; starting `Scripts/verify.sh` now.

## Re L-009 step 1 — done: all green locally (Xcode 27.0, head 1e91e4c)
`Scripts/verify.sh --keep-going`: toolchain, generate, lint, build PASS; unit **302 pass / 0 fail / 1 skip**; UI 49/50.
The one UI failure, `SearchRemindersUITests.testReminderSwitchesStartOff` ("settings.remindTasks should start off",
got "1"), was my own residue: L-009 step 2 turned the switch on, and it is `@AppStorage` (UserDefaults), which
survives relaunches and is not reset by `-uiTesting`. After uninstalling the app, the class passes (2/2). CI is
unaffected (fresh simulator), but consider having `-uiTesting` use a throwaway UserDefaults suite or clear the
reminder keys, so a hand walk can't break the suite. Launch metric this run: 1.160 s average.
Local queue is now empty (L-001…L-010 all answered). Simulator restored to en-CA; Household Hub uninstalled.

## Re L-011 — taken

## Re L-011 — done: not an app bug, my tap tool; finding retracted (96b26c8, build 8c58645)
Goal editor, light, default size. With the Simulator tool's instant `tap` (touch-down/up with ~0 ms between):
1. Target (FocusingRow) focused → one tap on Target date: **swallowed**.
2. Name (plain TextField, not a FocusingRow) focused → one tap: **swallowed**.
Control: no field focused, no keyboard → one instant tap: **also swallowed** (twice in a row).
With a realistic press (touch held 100 ms via touch_path): no keyboard → toggles first time; Target focused, keyboard up →
**toggles first time**. So the iOS 26 switch ignores zero-duration synthetic taps; FocusingRow and the keyboard are
not involved. Step 3 skipped (no defect left to attribute; avoided editing code). Screenshots
`docs/walk/sprint-12/local/L-011-*.png`. XCUITest's `tap()` is a normal-length touch, so UI tests are unaffected.

## Re L-012 — taken

## Re L-012 — blocked by a defect: "Back up now" does nothing (7f20a0d, build d5cdca2, fresh install, English)
Setup worked: onboarding with a $1,000 starting balance, Quick Add "42.10 groceries" and "15 lunch" (balance $942.90,
spent $57.10), wishlist "Bike" $300 with a Photos image (shows on the item). Screenshots `docs/walk/sprint-6/local/01…05`.
Settings › Backup and export › **Back up now**: tapped three times, waited 4 s: no save sheet, no message, no log error.
**Export transactions as CSV** on the same screen opens the Files save sheet at once (On My iPhone), so the document
picker itself is drivable (`06-csv-export-sheet.png`; cancelled, nothing saved).
Likely cause: `DataView.swift` chains two `.fileExporter` modifiers on the same view (backup at ~line 83, CSV at ~89).
SwiftUI honours only one presentation modifier of the same kind per view; the later one (CSV) wins, so the backup
exporter's `isPresented` never presents. Fix idea: one `.fileExporter` driven by an enum/item, or attach the backup
exporter to a different view (e.g. the Backup Section). The code dates from Sprint 6 (3e9d278); unit tests cover the
backup data, not the presentation, so CI can't see it. Restore not tried (no backup to pick). Ping me after the fix and
I'll run L-012 end to end. Also: the Settings row says "Backup and export" but the screen is titled "Data".

## Re L-012 rerun — taken (9b100f5)

## Re L-012 — done, passes end to end (0db76f1, build 774d0c4, fresh install, English)
Before: $1,000 start, "42.10 groceries" + "15 lunch" → Current balance $942.90, Spent this week $57.10; wishlist "Bike"
$300 with a Photos image. **Back up now** opens the Files save sheet; saved "Household Hub Backup 2026-09-27" in On My
iPhone → "Backup saved." (folder: backup.json 8 KB + Media/Wishlist/<uuid>.jpg). **Export transactions as CSV** still
opens its save sheet (cancelled). Uninstalled Household Hub only, reinstalled (the backup folder survived in Files),
onboarded with $0, **Restore from backup…** → Browse › On My iPhone › the folder › Open → "Replace all data?"
"Everything is replaced by the Sep 27, 2026 at 8:34 AM backup (2 transactions, CAD). Wishlist photos are replaced
too. This can't be undone." → Replace → "Restored 2 transactions." After: $942.90, $57.10, both transactions, Bike
with the same photo, $300, Medium, Wanted. Screenshots `docs/walk/sprint-6/local/rerun-01…11`. No defects.

## Local status — ready for new items; installing on the owner's iPhone (owner request)
Queue empty on my side (L-001…L-012 answered); the 15-minute poll is running. Owner asked to install the app on
their iPhone now. Heads-up per CLAUDE.md §4: this is the **first install on the owner's device**, so SchemaV1 stops
being editable from here on; any model change after this needs SchemaV2 + a migration stage. Build will be 7153107
(or later), Debug, Personal Team signing (Automatic, passed on the command line; project.yml unchanged). I'll report
the install and any on-device-only checks (Face ID gate, widget, Shortcuts) you want queued as L-013+.

## Local status — app installed on the owner's iPhone (063a510, Debug)
Owner's iPhone 16 Pro Max, iOS 27.0 (24A437), paired, Developer Mode on. Built with Personal Team Q2M932GVLA
(automatic signing on the command line, profiles "iOS Team Provisioning Profile: dev.householdhub.app" and ".widget";
project.yml unchanged) and installed with devicectl. **SchemaV1 is now frozen** (first install on the owner's device):
from here every model change needs SchemaV2 + a migration stage. Free-team signing expires in 7 days; I reinstall on
request. Ready to take device-only checks from WALK-QUEUE (Face ID gate, widget, Shortcuts, live AI) as L-013+.

## Re L-013 — done (installed before this item arrived; details in "app installed on the owner's iPhone" above)
Installed commit: the Debug build from 7153107-level code (no app code changed between 7153107 and 063a510), bundle
prefix `dev.householdhub` (default, no conflict), no signing errors. Owner is trusting the developer on the phone.
Sorry: my earlier note above includes the Team ID; I only saw the "don't commit it" rule afterwards. I have not
rewritten the file (append-only rule). A Team ID is visible in any app it signs, but if you want it gone from the
current file, say so and I'll edit that line in a new commit. `Scripts/install-device.sh` (Release) built fine at
ee0bf2b; its install step failed only because the phone went unavailable (locked):
"The device is not able to fulfill the requested usage assertion requirements. (CoreDeviceError 4016)".
I'll rerun it when the owner unlocks the phone, then start L-014 with them.

## Re L-015 — taken (23f85a3)

## Re L-015 step 1 — lint clean, build OK, unit 315/0/1 (5856e8c, Xcode 27.0)
Sprint 17 compiles as written: no compiler errors, swift-format --strict clean. Unit tests pass (315 passed, 0 failed, 1 skipped). UI tests running locally now; step 2 (Release reinstall) waits for green CI and the phone (currently unavailable/locked).

## Re L-015 — UI tests green locally (53/53)
Same head as the unit run: UI tests passed 53, failed 0 (includes BatchAddUITests). So Sprint 17 is fully green on this Mac (Xcode 27.0). Waiting for green CI on the Sprint 17 head, then the Release reinstall when the owner unlocks the phone.

## Re L-016 (+ L-015 step 1 repeat) — taken (1f63892)

## Re L-016 step 1 — lint FAIL, build FAIL (test target only) (7fd0dc1, Xcode 27.0)
swift-format lint --strict:
```
HouseholdHubApp/Features/Tasks/TasksView.swift:172:24: error: [AddLines] add 1 line break
HouseholdHubApp/Features/Tasks/TasksView.swift:172:76: error: [AddLines] add 1 line break
HouseholdHubApp/Features/Tasks/TasksView.swift:184:24: error: [AddLines] add 1 line break
HouseholdHubApp/Features/Tasks/TasksView.swift:184:74: error: [AddLines] add 1 line break
```
Build (build-for-testing) — two errors, same cause, both in `HouseholdHubTests/ThemeWordingTests.swift`:
```
ThemeWordingTests.swift:30 @Test(arguments: themes) … namesTheUserChoseAreKept
ThemeWordingTests.swift:48 @Test(arguments: themes) … everyThemeHasAllItsWords
macro expansion @Test:16:26: error: main actor-isolated static property 'themes' cannot be accessed from outside of the actor
```
The struct is `@MainActor`, so `static let themes` (line 11) is main-actor isolated, and the @Test macro evaluates
`arguments:` nonisolated. Likely fix: `nonisolated static let themes = …` (FunTheme is Sendable), or move the list out
of the struct. `FunThemeTests.swift:8` has the same pattern but no error (that struct isn't @MainActor). App, Core
and Widget targets compiled; unit/UI tests not run (test target doesn't build). L-015 step 1 repeat: same result.

## Re L-016 rerun — lint clean; build FAIL, one new error (7f89349)
The earlier findings are fixed (swift-format clean; ThemeWordingTests compiles). New in 7f89349:
```
HouseholdHubUITests/TasksUITests.swift:217:10: error: declaration can not have multiple global actor attributes ('MainActor' and 'MainActor')
```
`columnHeader(_:_:)` has `@MainActor` twice: line 214 (above the doc comment) and line 216. Delete one (keep the one
after the doc comment). Unit/UI tests not run; I'll rerun on your next push.

## Re L-016 rerun 2 — lint clean, build OK; unit 334 pass / 1 FAIL (6a58fb9)
```
HouseholdHubTests / batchCreatedItemsSurviveABackupRoundTrip(): Expectation failed: again == exported
```
(BatchAddTests.swift:257, `#expect(again == exported)`.) The two BackupDTO descriptions are character-for-character
identical (4449 chars), so the difference is below what `description` prints: most likely a Date differing below the
second (the snapshot's `exportedAt`/timestamps vs. values that went through the millisecond ISO encoder), or a
Double/Decimal field. Comparing the DTOs field by field (or the encoded JSON of both) will show it. UI tests not run
yet; starting the Sprint 19 theme screenshots for the owner now (L-016 step 3).

## Re L-016 step 3 / L-015 step 3 — Simulator walk of Sprints 17–19 (cfba4cb, build 6a58fb9)
Screenshots: `docs/walk/sprint-19/local/<theme>-dashboard.png`, `<theme>-tasks.png`, `style-picker.png`;
`docs/walk/sprint-17/local/`. Owner has been sent the theme set.
- Add several (Sprint 17): pasted 4 task lines → preview "4 to add", "Call plumber friday" → due Fri Oct 2, "tomorrow" →
  Sep 28; Add saved all 4. Wishlist: "250 new bike / $1,200 sofa / headphones" → $250, $1,200, Price unknown. Works.
- Themes (Sprint 19): all five apply instantly (background tint, accent, title font, tab icons, themed column names:
  Waiting to play / Ready for takeoff / In the nest / Sweet to-dos / Bundling up). Airplanes and Winter draw faint
  decorations (clouds/planes, snowflakes). Nothing broken or unreadable.
Observations (minor):
1. Selecting a Style pops you back to the Settings root instead of staying on the Style list.
2. Tasks board (all themes): the first column starts ~55 pt from the left edge, leaving an empty strip, while the next
   column is cut off on the right. Looks like the paging offset assumes a centred column.
3. The theme doesn't reach the list icons: wishlist rows keep the plain gray gift placeholder.
Still open: the batch-add backup round-trip unit failure above; UI tests not yet run on 6a58fb9.

## Re L-016 step 2 — UI tests 58/59, one failure (6a58fb9, Xcode 27.0)
```
ThemesUITests.swift:24: testStyleCanBeChosenAndTurnedOff(): Failed to get matching snapshot: No matches found for
Elements matching predicate '"settings.accent" IN identifiers'
```
Line 24 is `XCTAssertFalse(app.buttons["settings.accent"].isEnabled, …)` right after `chooseStyle(app, "Toy Box")`.
Likely cause is my walk observation #1: choosing a Style pops back to the Settings root scrolled to the top, so the
Accent row (under Appearance, below the fold) isn't in the tree. Either keep the user on the Appearance section after
choosing (better UX), or `scrollUntilExists(app, app.buttons["settings.accent"])` before the assertion. All other UI
tests pass, including TasksUITests and BatchAddUITests. Remaining red items: this one and the batch-add backup
round-trip unit test.

## Re L-016 rerun 3 — lint clean, build OK; unit 334 pass / 1 FAIL (10478aa)
```
HouseholdHubTests / batchCreatedItemsSurviveABackupRoundTrip(): Expectation failed:
abs(restored.createdAt.timeIntervalSince(original.createdAt)) < 0.0005 → 0.0009999275207519531
```
Cause: `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` **truncates** to the millisecond, it doesn't
round. Checked on this Mac: …20.9996 → ".999Z" (−0.60 ms), …20.12389 → ".123Z" (−0.89 ms). So a round trip loses
up to <1 ms, and the test's 0.5 ms bound fails whenever the sub-millisecond part is ≥ 0.5. Fix either side: the test
bound `< 0.001` (matches the documented "to the millisecond"), or make it exact by flooring the snapshot's
timestamps to whole milliseconds before comparing. Flaky by clock, so CI may pass or fail on any run.
Retaking the three screenshots and running UI tests next.

## Re L-016 rerun 3 — UI tests 58/59 (e6ce130)
Same single failure as before, unchanged by the walk fixes: `ThemesUITests.testStyleCanBeChosenAndTurnedOff` at line 24, "No matches found for ... \"settings.accent\"". Since the pop-back to the Settings root is by design, the test needs to scroll to the Accent row (`scrollUntilExists(app, app.buttons[\"settings.accent\"])`) before both accent assertions (lines 24 and the final one). Everything else passes. Red items now: this test and the batch backup round trip (ISO8601 truncation).

## Re L-017 — taken (f3ede48); will not install on the phone

## Re L-017 step 1 — lint clean, build OK; unit 360 pass / 2 FAIL (11692fa)
**Migration passes:** `PersistenceTests/aSchemaV1StoreOnDiskMigratesToSchemaV2WithEveryRecord` ✔ (0.040 s).
Failures:
```
HouseholdHubTests / aPurchaseWithRefundsKeepsWhatTheyDependOn(): Caught error: .purchaseHasRefunds
  (recorded at RefundTests.swift:175:6 — the uncaught throw of the last, un-#expect'ed call)
HouseholdHubTests / batchCreatedItemsSurviveABackupRoundTrip(): … < 0.0005 → 0.0009999275207519531  (unchanged, see above)
```
RefundTests cause: the final "allowed" step `update(purchase, with: draft(4_000, .expense, .pending))` sets the purchase
to **pending**, but `refund(purchase, 4_000, in:)` defaults to `status: .posted`, and
`requireRefundsStillFit` (TransactionService+Refunds.swift:203–206) rejects `status == .pending && live.contains { posted }`
— your decision 6 ("pending only while no refund is posted"). So the code follows the decision and the test's
comment ("a pending status is fine") contradicts it. Fix the test: keep `.posted` in that last draft (or make the
refund pending), whichever the decision intends. All other RefundTests pass. UI tests next.

## Re L-017 step 2 — UI tests 60/62
```
RefundUITests.swift:62: testRefundingAWishlistPurchaseAsksToKeepTheItem(): Failed to tap "Keep on wishlist" Button:
Multiple matching elements found
  ↳Alert 'Keep it on your wishlist?' ↳Button id 'refund.keep' (twice, nested: the alert's button + its label)
  ↳Button id 'editor.keepOnWishlist'   (the TransactionEditorView fallback row, still in the tree behind the alert)
ThemesUITests.swift:24: testStyleCanBeChosenAndTurnedOff(): No matches found for "settings.accent"  (unchanged)
```
Refund fix: query by identifier, e.g. `app.alerts.buttons["refund.keep"].firstMatch` (or `app.buttons["refund.keep"].firstMatch`)
instead of the label "Keep on wishlist", which the editor's fallback row shares. The app behaviour looks right: the alert
appeared. Other RefundUITests, TasksUITests pass.
Summary of red on this head: unit ×2 (refund decision-6 test, backup ms truncation), UI ×2 (refund.keep query, themes
accent scroll). Not installing on the phone (L-017 step 3).

## Re L-017 rerun — unit 362/0/1 on ee240e2+ (fd7e67e); UI running. Owner-directed install done.
Lint clean, build OK, **unit tests all pass** (362 passed, 0 failed, 1 skipped): batch round trip, RefundTests and the
V1→V2 migration included. UI tests in progress; result follows.
**Owner decision (explicit, overrides L-017 step 3):** the owner asked to install the latest version now and confirmed the
phone's Household Hub held **no data to keep**, so no backup was taken. Installed Release at fd7e67e (SchemaV2) on the
owner's iPhone 16 Pro Max (iOS 27.0) with devicectl; it launched. CI had not finished green at the time.
(Held this push per the CI pause; pushed after the run completed.)
**L-017 UI result (fd7e67e): 61/62.** ThemesUITests now passes. Only failure left, as reported earlier:
`RefundUITests.swift:62 testRefundingAWishlistPurchaseAsksToKeepTheItem(): Failed to tap "Keep on wishlist" Button:
Multiple matching elements found` (alert's `refund.keep` vs the editor's `editor.keepOnWishlist`, same label). Query by
identifier (`app.alerts.buttons["refund.keep"].firstMatch`).

## Re L-018 — verify: lint/build OK; unit 361/1; UI 58/2 (14cba23)
Unit:
```
HouseholdHubTests / batchCreatedItemsSurviveABackupRoundTrip(): Expectation failed: names == ["bike", "headphones", "sofa"]
  names → ["bike", "sofa", "headphones"]   (BatchAddTests.swift:273)
```
The batch items share one `createdAt` (same `now`), so sorting by `createdAt` after restore is a tie and the order is
arbitrary. Sort by a real tiebreaker (sortOrder, or name) or compare as sets. Flaky, not a data problem.
UI:
```
TasksUITests.swift:90 testColumnsAreTwoThirdsWideAndADropFocusesTheNextColumn(): ("-176.0") is not equal to ("28.0") +/- 8 — In Progress was not focused
RefundUITests.swift:65 testRefundingAWishlistPurchaseAsksToKeepTheItem(): Failed to tap "Keep on wishlist": Multiple matching elements
```
- Tasks: **real bug, reproduced by hand.** Dragging a To Do card and resting it on the right-edge peek for ~1 s
  spring-loads **two** columns: the board went past In Progress to Done and the card dropped into Done (marked done).
  The test's -176 is the same thing (In Progress scrolled off to the left). The spring-load needs to fire once per
  entry into the edge (or wait ≥ ~1 s between repeats). Screenshot: `docs/walk/sprint-18/local/` not taken for this; easy to repeat.
- Refund: `alert.buttons["Keep on wishlist"]` still matches twice **inside the alert** (iOS 26 nests a Button in the
  Button, both id `refund.keep`). Use `alert.buttons["refund.keep"].firstMatch`.
L-018 step 2 (left-edge strip): not verifiable with my tools. On the Done card, every long-press-then-drag I send opens
the context menu (Reopen / Move to… / Delete) instead of lifting the card (`board-left-longpress-opens-menu.png`),
while the same gesture lifted a To Do card earlier. Either done cards don't drag, or leftward drags lose to the menu.
Needs the owner's finger on the Simulator or the phone.

## Re L-019 — taken (d587446)
L-019 step 1 on 4c4ed64: lint clean, build OK, **unit 367 passed / 0 failed** (ThemeArtTests included). Screenshots next.

## Re L-019 — steps 1, 2, 4 done; step 3 needs the owner; L-018 spring-load still skips a column (ebfaa71)
Screenshots (Simulator sample data only, no real data): `docs/walk/sprint-21/local/` — Toy Box
`<dashboard|budget|wishlist|tasks|more>-<dark|light>.png`, and `<loveMom|airplanes|winter|dinosaurs>-dashboard-<dark|light>.png`.
Owner has been sent a comparison sheet of all five Dashboards.
Works: every theme shows its own drawings (Love Mom: "love" script, mother and child, teddy, flowers, mug; Airplanes:
planes, helicopter, paper plane, suitcase, sun and cloud; Winter: snowflakes, snowman, penguin, polar bear, cabin, sled;
Dinosaurs: volcano, pterodactyl, dinosaurs, egg, palm). Dark = chalkboard, light = paper; chalk-edged cards and rows on
every tab; crayon Add buttons; theme fonts on titles and amounts.
Findings:
1. **Drawn cloud behind the toolbar** on Budget, Wishlist and Tasks (top right): it sits under the filter / add-several /
   + buttons and clashes with them (`budget-*`, `wishlist-*`, `tasks-*`). Move it left or drop it where there's a toolbar.
2. **Task cards aren't themed**: in dark they're solid black blocks on the chalkboard; in light plain white with no chalk
   edge, while the columns around them are chalk-edged (`tasks-dark.png`, `tasks-light.png`).
3. The floating + covers the right end of the last Recent activity row on the Dashboard (amounts cut off) in all themes.
Step 3 (compare with the owner's mockup): I don't have the mockup (not in the repo), so the owner has to compare.
**L-018 re-try, still wrong:** Tasks, Toy Box light. Drag "Call plumber" from Waiting to play and rest on the right edge
~2.3 s: the board went **two columns**, to "Put away", and on release the card was dropped nowhere (it stayed in
Waiting to play; Playing is empty). So the spring-load still repeats while resting at the edge (build includes ad395c5).
Screenshot `l018-springload-once.png`.

## Re L-020 — taken (bb5e396); no phone install

## Re L-020 step 1 — lint clean, build OK; unit 387 pass / 1 FAIL (5f90b10)
PersistenceTests (V2→V3 on disk, V1→V3), RecurringPurchaseTests and BackupTests all **pass**. One failure, a stale literal:
```
HouseholdHubTests / refundsRoundTripThroughABackup(): Expectation failed: exported.schemaVersion == 3 → 4
```
RefundTests.swift:354 expects backup format 3; `BackupDTO.currentSchemaVersion` is now 4 (Sprint 22). Use
`BackupDTO.currentSchemaVersion` instead of the literal.

## Re L-020 step 5 — frozen schema hashes
`Schema.Entity` has no public `versionHash` (compile error), so I used Core Data's:
`NSManagedObjectModel.makeManagedObjectModel(for: SchemaVn.models)!.entities` → `entity.versionHash.base64EncodedString()`.
At **fd7e67e** (scratch worktree, test not committed, worktree removed):
```
V1 Account z8vYhvnjK/te4y7y6DljMmwO+2iy1UuwpSEpB6yfsqE=
V1 AppSettings PclbrgFUgnyPFx/XBhB/qKu92jpbLQm1COGAXlhf8DA=
V1 BoardColumn otW/nUsNm6JmixgMPaSfXzQKcN4TpRQPPUGsn7jnXCc=
V1 CategoryBudget VAEI6gouN4/Rxh1sazObIrp0WmXZkaJGB1U2nLhNQ+A=
V1 CategoryRecord cUsNCAgPc2gpLihb3KPSdaNKvFO7/B4U9Vl+JpBMpUw=
V1 Merchant s6+cFd3vZXSEfg7LVPwvIgyni9MzWu0zbh7rFZUjNzU=
V1 RecurringTransaction oijWj8kd4Qliu8X7ya4opWf6YHpcszEX9uqplqLYJdA=
V1 SavingsGoal mUZ5lA3rraIbpy7Wa46GGYVKa+Y0V370fRnsYN0UATY=
V1 SubtaskItem vZQ3n0NYJGO8BxsXX4uo3anzMtE0fKjDyV46vRtmHnU=
V1 TaskItem zSCRBvZul4FQCWPnYOzgXEGlpyDbzbi73NGZo+Dhulo=
V1 TransactionRecord 9eg/co5II3NEWXB1AlD8Tjiu7K1d4lP9xi5cCoyiE20=
V1 WishlistItem bPgBJmmAIe2iJw9B3LFaHmdIJSBZZgJ+vxJH74SqYPo=
V2 Account z8vYhvnjK/te4y7y6DljMmwO+2iy1UuwpSEpB6yfsqE=
V2 AppSettings PclbrgFUgnyPFx/XBhB/qKu92jpbLQm1COGAXlhf8DA=
V2 BoardColumn otW/nUsNm6JmixgMPaSfXzQKcN4TpRQPPUGsn7jnXCc=
V2 CategoryBudget VAEI6gouN4/Rxh1sazObIrp0WmXZkaJGB1U2nLhNQ+A=
V2 CategoryRecord cUsNCAgPc2gpLihb3KPSdaNKvFO7/B4U9Vl+JpBMpUw=
V2 Merchant s6+cFd3vZXSEfg7LVPwvIgyni9MzWu0zbh7rFZUjNzU=
V2 RecurringTransaction oijWj8kd4Qliu8X7ya4opWf6YHpcszEX9uqplqLYJdA=
V2 SavingsGoal mUZ5lA3rraIbpy7Wa46GGYVKa+Y0V370fRnsYN0UATY=
V2 SubtaskItem vZQ3n0NYJGO8BxsXX4uo3anzMtE0fKjDyV46vRtmHnU=
V2 TaskItem zSCRBvZul4FQCWPnYOzgXEGlpyDbzbi73NGZo+Dhulo=
V2 TransactionRecord 2g9ao8KCDDqQBAa3ERmZEHquayXhZfIjTQzbqhK+Nm0=
V2 WishlistItem bPgBJmmAIe2iJw9B3LFaHmdIJSBZZgJ+vxJH74SqYPo=
```
Same dump on **today's head** (temporary test, deleted, not committed): V1 and V2 are **byte-identical** to the lists above,
so nothing frozen has drifted. SchemaV3 differs only in `RecurringTransaction` → `Ah+kRpqWLOcB/TVzas/mI6QzL9RoRU2wsiRDA2BS7M4=`
(TransactionRecord is V2's `2g9ao8K…`; the rest are V1's). Only TransactionRecord differs V1→V2, as intended.
FrozenSchemaTests: yours to add (the snippet above is all it needs). UI tests (step 2) and the spring-load re-try (step 3) next.

## Owner-directed install of 8a9ec36 (SchemaV3) on the owner's iPhone — overrides L-020 step 4
The owner asked to install now and confirmed the app on the phone holds **nothing to keep**, so no backup was taken.
Release build at 8a9ec36, installed over the fd7e67e (SchemaV2) install with devicectl; the app **launched** (so the
V2→V3 lightweight migration opened the existing store). CI had not finished green. **SchemaV3 is now on the owner's
device: treat it as frozen** (next stored change is SchemaV4), and add its hashes to FrozenSchemaTests (V3 list in my
step 5 report).
