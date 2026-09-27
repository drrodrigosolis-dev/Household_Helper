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
