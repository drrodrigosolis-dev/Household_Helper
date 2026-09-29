# Sprint 24 — v1.1: first-time tutorial (CI green; owner walk pending)

Owner request 2026-09-28: a detailed first-time user experience tutorial where highlights and short callouts teach
everything the app can do. Siri moved to Sprint 25.

## Shape (owner agreed 2026-09-28)
1. **First-run tour** after onboarding: 5–7 stops over the essentials (Dashboard figures, Quick Add, Budget, Wishlist
   → purchase, Tasks board, More › Settings). A spotlight dims the screen around the highlighted control with a
   short callout (one or two lines), Next / Skip, a step count. Skippable at any time; never blocks the app.
2. **Contextual tips** the first time each deeper feature is in reach (split, undo, bulk select, saved searches,
   import presets, recurring suggestions, refunds, themes, budget history, analytics taps) with Apple's TipKit
   (free, iOS 17+; check its iOS 26 API first with household-research-apple-api).
3. **Replay** from Settings ("Show the tour again", "Reset tips").
4. **Accessibility:** every callout is read by VoiceOver and usable without seeing the highlight; respects Reduce
   Motion, Dynamic Type (callouts wrap, never truncate), both languages, every theme, light and dark.
5. **State** in device settings (UserDefaults / TipKit's store), not in SwiftData or backups; UI tests reset it.
6. **Tests:** a UI test per tour stop with screenshots in every appearance, so a layout change that breaks a stop
   fails CI; unit tests for the tour/tip state logic.

## Owner answers (2026-09-28)
- **Tour: 6 stops.** Dashboard figures → Quick Add → Budget list → Wishlist (a purchase becomes an expense) → Tasks
  board → More › Settings (themes, replay). About a minute.
- **Existing install (the owner's phone):** a one-time, dismissible "New: take the tour" offer; contextual tips then
  appear as each feature comes into reach. Fresh installs start the tour after onboarding.
- **Copy:** plain and warm, one text for every theme, English and Spanish.
- Quiet hours lifted for 2026-09-28 (owner).

## Items
| # | Item | Built | Walked |
|---|---|---|---|
| 1 | Tour engine: spotlight + callout, Next/Skip, step count, VoiceOver, Reduce Motion, Dynamic Type | ☑ | ☑ L-026 hand walk, `Sprint24TourUITests` screenshots (light; dark at large text, L-027); VoiceOver focus and hidden app behind (c7734ea): L-034 walk pending |
| 2 | The 6 stops, and the tour starting after onboarding | ☑ | ☑ L-026 (all 6 stops by hand, `docs/walk/l026-tour/`), L-027 (every tour test passes on the Mac) |
| 3 | Existing-install offer, shown once | ☑ | ☑ `Sprint24TourUITests.testNotNowDismissesTheOffer` screenshot |
| 4 | Contextual tips (split, undo, bulk select, saved searches, import presets, recurring suggestions, refunds, themes, budget history, analytics taps) | ☑ | ☐ 3 of 10 seen in `Sprint24TipsUITests` screenshots, light and dark (bulk select, split, budget history); the rest need the owner's walk (L-034 walk pending); catalog by `TutorialTipsTests` |
| 5 | Settings: Show the tour again · Reset tips | ☑ | ☑ `Sprint24TourUITests.testSettingsShowsTheTourAgain` screenshots (Show the Tour Again); Reset Tips not seen |
| 6 | State in UserDefaults / TipKit store; UI-test launch arguments reset it; unit tests for the state logic | ☑ | ☑ walked by its tests (`TourLaunchPolicyTests`, `TutorialTipsTests`; domain only) |
| 7 | UI test per stop with screenshots (light, dark, large type) | ☑ | ☑ the tests themselves: green in 36599247241 and on the Mac (L-027, L-033 88/88) |

Research first: `household-research-apple-api` on TipKit (iOS 26) and a pure-SwiftUI spotlight; decision recorded in
`docs/research/apple-api-decisions.md`.

## Close-out (2026-09-29)
☑ CI green: run 36599247241 on `dba6f9e` (lint, build, unit, UI 88/88); the Mac's full UI suite 88/88 on the same code
(L-033). ☑ research recorded (TipKit vs custom spotlight). ☑ accessibility audit (c7734ea). ☑ PROGRESS row · ☑ PR #2 body.

- **Shipped:** the spotlight tour (six stops, Next/Skip, step count), started after onboarding; the one-time "New: take
  the tour" offer on existing installs; ten TipKit contextual tips; Settings › Tutorial (Show the Tour Again, Reset
  Tips); English and Spanish copy.
- **Walked:** all six stops by hand on the Mac (L-026) and by `Sprint24TourUITests` screenshots, including dark at large
  text; the offer, the replay, and three tips by UI-test screenshots.
- **The walk fixed:** stops pointing at the wrong place on the owner's phone (41d9cce); empty screens point at their
  empty-state message, in-form tips inline (d891007); stop 3's spotlight check (719fe0d); stop 1 at accessibility sizes
  spotlights the Current card (dcfbdc7); the tips test reaching Budgets (199bbc8, 600db9a, f36b82e); the accessibility
  audit's VoiceOver focus, full-size buttons, side docking at large sizes and the Tasks stop naming Move to… (c7734ea).
- **Still needs the owner (L-034 walk pending):** the tour from Settings with VoiceOver on (focus on each header, the
  app behind unreachable); the remaining seven tips in place; Reset Tips.
- **Open decisions:** none.
