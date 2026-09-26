# Apple API decisions

One entry per version-sensitive decision (§19.2): API/framework, minimum OS, Xcode/Swift tested, entitlements,
availability conditions, deprecations, fallback. Verified against official Apple documentation
(`household-research-apple-api` skill).

## Project baseline — 2026-09-25
- Deployment target iOS 26.0, iPhone only; Swift 6 language mode, strict concurrency complete, warnings as errors.
- Swift Testing for unit tests, XCTest for UI tests (§13). Toolchain: whichever Xcode the CI runner selects with
  an iOS ≥ 26 simulator SDK (recorded in each run's "Select Xcode" step).

## SwiftData modelling choices — Sprint 1, 2026-09-25
- **Names:** `TransactionRecord` (SwiftUI has `Transaction`) and `CategoryRecord` (the ObjectiveC module exports
  `Category`, visible wherever Foundation is imported). Same reasoning as the spec's `TaskItem`.
- **Enums stored as raw `String` columns** with typed computed accessors, so they can be used in `#Predicate`
  (SwiftData predicates cannot compare Codable enum attributes).
- **`RecurrenceRule` stored as JSON `Data`**: enums with associated values have been unreliable as SwiftData
  composite attributes. `ColorToken` (a plain Codable struct) is stored directly.
- **No `.unique` on `Merchant.normalizedName`**: a unique-constraint clash in SwiftData upserts (silently replaces
  the existing row). Uniqueness is enforced by `TransactionService.findOrCreateMerchant`.
- **UUID references, not relationships**, as §7 lists them; services enforce integrity and backup DTOs (§26) map
  one-to-one.
- **Services are `@ModelActor` actors** created through `make(container:)`, so the app never depends on the
  macro-generated initializer's access level.
- **Model actor contexts must not be left dirty:** a method validates everything before its first mutation,
  because an unsaved edit left after a throw would be persisted by the actor's next `save()`.

## Task board and cross-context writes — Sprint 4, 2026-09-26
- **`TaskBoardService` starts every write from a clean context** (`begin()` rolls back leftover edits), on top of
  rollback-on-failed-save, so a fetch that throws mid-operation cannot leave edits for a later save. The other
  services keep the "fetch everything before the first edit" rule above.
- **Two actors write `TaskItem`:** `TaskBoardService` (all board edits) and `TransactionService` (clears
  `linkedWishlistItemID` when it deletes a wishlist item). They touch different fields, and the link is re-checked
  on every task save, where a stale link is dropped. **Unverified assumption:** when both contexts save the same
  object, SwiftData's default merge keeps the later save's values for the fields it changed. This has not been
  checked against Apple documentation or a test; if it proves wrong, route the link clearing through
  `TaskBoardService`. Recorded for the Phase 10 verification pass.
- **Subtasks link by `taskID`, not a relationship** (Sprint 4 default 4): there is no store-level cascade, so every
  bulk delete path (task delete today; restore-replace or reset later) must delete subtasks explicitly.

## Swift Charts and audio graphs — Sprint 5, 2026-09-26
- **Swift Charts** (system framework, iOS 16+; `SectorMark` and `chartAngleSelection` iOS 17+, below our iOS 26
  floor): no dependency record needed. Values are plotted as `Double` for positioning only; every figure shown as
  text comes from the exact `Money`.
- **Chart accessibility (spec §24.5):** each chart sets `accessibilityChartDescriptor` (`AXChartDescriptor` from the
  Accessibility framework, iOS 15+) and repeats its numbers in a visible table, so nothing exists only as an image.
- **Slice selection:** `chartAngleSelection` reports the selected value on the angle scale (cumulative amount), which
  the view maps back to a slice; the table rows are the non-gesture path to the same action.
- Not yet verified against Apple documentation in this session (no network docs access here); CI compiling and
  the walk rendering are the check. Revisit in the Phase 10 verification pass.

## Foundation Models (on-device AI) — Sprint 7, 2026-09-26
- **Framework:** `FoundationModels` (iOS 26): `SystemLanguageModel.default.availability`, `LanguageModelSession`
  (`instructions:`), `respond(to:)` and `respond(to:generating:)` with a `@Generable` struct whose fields carry
  `@Guide` descriptions. Used only in `HouseholdHubCore/Intelligence/OnDeviceModel.swift`, behind
  `#if canImport(FoundationModels)` and an availability check; every call returns nil when unavailable.
- **Generated fields are plain strings and an integer**, not optionals or Double (amount travels as text and is
  parsed as `Decimal`), to keep the structured output simple and money exact.
- **Verified 2026-09-26 against Apple's documentation** (foundationmodels/systemlanguagemodel/availability-swift.enum,
  foundationmodels/languagemodelsession, "Generating Swift data structures with guided generation", WWDC25 286):
  availability is `.available` / `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`;
  `respond(to:generating:)` returns a `Response` read through `.content`; `@Guide(description:)` is valid on `Int`
  fields (a `.range` guide is also available). Context window 4,096 tokens; one request per session at a time, so
  a new session per call is correct. Behaviour still needs a device with Apple Intelligence (WALK-QUEUE). The CI
  simulator is unreliable (usually unavailable; once available and failing every request), so live fixtures are
  opt-in (`TEST_RUNNER_HH_LIVE_AI=1`).

## Widget and App Intents — Sprint 8, 2026-09-26
- **Verified against Apple's documentation** (widgetkit/timelineprovider, widgetkit/staticconfiguration,
  widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity,
  widgetkit/adding-interactivity-to-widgets-and-live-activities, appintents/appintent, appintents/supportedmodes,
  appintents/openappwhenrun, appintents/requestconfirmation(conditions:actionname:dialog:), xcode/configuring-app-groups,
  foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:), WWDC25 275 and 244).
- **Widget:** `StaticConfiguration` + `TimelineProvider` (completion-handler API; the async one belongs to
  configurable widgets), `.supportedFamilies([.systemSmall, .systemMedium])`, `containerBackground(for: .widget)`,
  timeline policy `.never` with `WidgetCenter.shared.reloadTimelines(ofKind:)` after the app writes a snapshot.
  Taps: one `widgetURL` per hierarchy (small), `Link` (medium); both arrive in `onOpenURL`. No entitlement needed.
- **Data:** the widget reads a JSON snapshot the app writes (Sprint 8 default 1), never the store.
  `containerURL(forSecurityApplicationGroupIdentifier:)` is nil on iOS when the group is invalid or not entitled;
  App Groups need a paid team, so the identifier is a build setting, empty by default, and the fixture provider is
  used whenever the URL is nil (§5.2).
- **App Intents (iOS 26):** `openAppWhenRun` is deprecated in favour of `supportedModes` (`.background`,
  `.foreground(.immediate)`); confirmation is `requestConfirmation(conditions:actionName:dialog:)`. Intents behind a
  widget `Button(intent:)` run in the extension, so the widget has no intent button; Shortcuts intents live in the
  app target and reach app state through `@Dependency` (`AppDependencyManager`).
- **Unverified (CI decides):** the extension building and running unsigned in the Simulator; the exact XcodeGen
  embedding (`app-extension` target, app `dependencies` with embed) and the `NSExtension` Info.plist dictionary.

## Face ID gate (LocalAuthentication) — Phase 10, 2026-09-26
- **API:** `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication, error:)` and
  `evaluatePolicy(.deviceOwnerAuthentication, localizedReason:) async throws -> Bool`; `biometryType` for the label.
  iOS 8+ (async form iOS 15+). No entitlement; needs `NSFaceIDUsageDescription` (set via
  `INFOPLIST_KEY_NSFaceIDUsageDescription`). Free Personal Team compatible.
- **Why `.deviceOwnerAuthentication`, not `...WithBiometrics`:** the passcode is the fallback, so a failed or
  unenrolled Face ID never locks the owner out. If the passcode is later removed the policy can't be evaluated; the
  gate then turns itself off (the device is unprotected anyway) rather than lock the data away.
- **Verification:** shapes from memory of the SDK, consistent with long-standing documentation; CI compiles it, and
  behaviour needs a device (WALK-QUEUE). The CI simulator has no passcode, so the Settings switch is disabled there.
