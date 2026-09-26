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
