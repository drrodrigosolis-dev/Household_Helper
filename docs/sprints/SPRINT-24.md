# Sprint 24 — v1.1: first-time tutorial (planned, starts after Sprint 23 closes)

Owner request 2026-09-28: a detailed first-time user experience tutorial where highlights and short callouts teach
everything the app can do. Siri moved to Sprint 25.

## Proposed shape (owner to confirm at sprint start)
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

## Open questions (one message with defaults at sprint start)
Tour length and stops; whether tips appear on the owner's phone immediately after the update (existing user) or only
on fresh installs; tone of the copy (plain vs. playful per theme).
