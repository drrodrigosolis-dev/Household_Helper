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
