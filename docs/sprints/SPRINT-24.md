# Sprint 24 — v1.1: first-time tutorial (building; closes after Sprint 23)

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
| 1 | Tour engine: spotlight + callout, Next/Skip, step count, VoiceOver, Reduce Motion, Dynamic Type | ☐ | ☐ |
| 2 | The 6 stops, and the tour starting after onboarding | ☐ | ☐ |
| 3 | Existing-install offer, shown once | ☐ | ☐ |
| 4 | Contextual tips (split, undo, bulk select, saved searches, import presets, recurring suggestions, refunds, themes, budget history, analytics taps) | ☐ | ☐ |
| 5 | Settings: Show the tour again · Reset tips | ☐ | ☐ |
| 6 | State in UserDefaults / TipKit store; UI-test launch arguments reset it; unit tests for the state logic | ☐ | ☐ |
| 7 | UI test per stop with screenshots (light, dark, large type) | ☐ | ☐ |

Research first: `household-research-apple-api` on TipKit (iOS 26) and a pure-SwiftUI spotlight; decision recorded in
`docs/research/apple-api-decisions.md`.
