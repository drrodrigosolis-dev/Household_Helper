# Apple API decisions

One entry per version-sensitive decision (§19.2): API/framework, minimum OS, Xcode/Swift tested, entitlements,
availability conditions, deprecations, fallback. Verified against official Apple documentation
(`household-research-apple-api` skill).

## Project baseline — 2026-09-25
- Deployment target iOS 26.0, iPhone only; Swift 6 language mode, strict concurrency complete, warnings as errors.
- Swift Testing for unit tests, XCTest for UI tests (§13). Toolchain: whichever Xcode the CI runner selects with
  an iOS ≥ 26 simulator SDK (recorded in each run's "Select Xcode" step).
