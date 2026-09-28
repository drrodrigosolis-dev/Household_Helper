# Open questions

- **Onscreen-content-for-Siri article's exact `introducedAt` OS version (Sprint 25 research, 2026-09-28).** The
  DocC JSON endpoint 404s for
  `documentation/appintents/making-onscreen-content-available-to-siri-and-apple-intelligence`, so the article's
  platform metadata could not be read the same way as the API reference pages in
  `docs/research/apple-api-decisions.md`. Do not build against the View Annotations API surface until this is
  confirmed against the toolchain in use.
- **Has spoken Siri (not just the Shortcuts app) been tried against `LogTransactionIntent` on the owner's
  free-Personal-Team device (Sprint 25 research, 2026-09-28)?** App Intents/App Shortcuts need no entitlement, but
  the device's own Siri/dictation setting is separate from signing and worth the owner confirming since Siri
  cannot run in CI.
- **§27 reference device unavailable on CI.** The macos-26 runner image (first green run 36192377205) has
  iPhone 17-series simulators on iOS 26.2/26.4/26.5 but no iPhone 16 Pro Max, so tests run on iPhone 17 Pro Max.
  Decide in Phase 10 whether performance tests should create an iPhone 16 Pro Max simulator
  (`xcrun simctl create`) or adopt the 17 Pro Max as the reference.
- **Bundle identifier prefix** is a placeholder (`dev.householdhub`, `project.yml` `BUNDLE_ID_PREFIX`). Change it
  before any physical-device install under a Personal Team.

## Resolved
- GitHub default branch set to `main` by the owner (2026-09-25).
- CI toolchain: `macos-latest` resolves to macos-26 with Xcode 26.0–26.6; the scripts select Xcode 26.6
  (iOS Simulator SDK 26.5, Swift 6.3.3).
