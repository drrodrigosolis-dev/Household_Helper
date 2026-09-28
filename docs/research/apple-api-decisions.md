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
  the existing row). Uniqueness is enforced by `TransactionService.findOrCreateMerchant`. The same holds for
  `CategoryBudget.categoryID` (Sprint 11): one budget per category is kept by `CategoryService.setBudget` and the
  backup validator, so a restore's merge-by-id never meets an upsert.
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
  app then opens for that session with an alert saying why, and the setting stays on so the lock returns as soon as
  a passcode is set (security review: it used to switch itself off for good). The Log Transaction shortcut asks
  for the same authentication when the lock is on, so it is not a way around the gate.
- **Verification:** shapes from memory of the SDK, consistent with long-standing documentation; CI compiles it, and
  behaviour needs a device (WALK-QUEUE). The CI simulator has no passcode, so the Settings switch is disabled there.

## Custom accent color (SwiftUI `Color.resolve(in:)`) — owner decision, 2026-09-26
- **API:** `Color.resolve(in: EnvironmentValues) -> Color.Resolved` (iOS 17+). `Color.Resolved.red/green/blue` are
  gamma-encoded sRGB components; `linearRed/linearGreen/linearBlue` are the linear ones and are not used. Values can
  fall outside 0...1 for extended-range colors, so they are clamped before becoming an opaque `ColorToken`.
- **Verification:** from memory of the SwiftUI SDK; a unit test (`LedgerFormatTests.resolvedColorsRoundTripToTheSameToken`)
  checks that every palette color survives `ColorToken → Color → resolve → ColorToken` unchanged, which would fail
  if the components were linear.

## UserNotifications — local reminders (Sprint 14, 2026-09-26)
- **API:** `UNUserNotificationCenter` with `UNCalendarNotificationTrigger` (non-repeating, one request per reminder,
  identifiers `task-<uuid>` / `bill-<series>-<occurrence>` so a reschedule replaces rather than duplicates).
- **Min OS / toolchain:** iOS 10+; async variants (`notificationSettings()`, `pendingNotificationRequests()`,
  `requestAuthorization(options:)`, `add(_:)`) iOS 15+. Project floor is iOS 26.
- **Entitlement / account:** none. Local notifications need no push entitlement, no APNs and no paid membership;
  they work under a free Personal Team and in the Simulator. No Info.plist key is required.
- **Limits:** iOS keeps at most 64 pending requests per app; the planner caps at 60, soonest first.
- **Permission:** asked only when the user turns a reminder switch on (never at launch); if refused, the switch
  goes back off and Settings explains where to allow it.
- **Fallback:** without permission nothing is scheduled; the app works the same.
- **Tests:** the plan is pure Core logic (`ReminderPlanner`, unit-tested); UI tests never touch notifications
  (`ReminderSync` returns early under `-uiTesting`).

## SwiftData schema versioning — SchemaV1 → SchemaV2 (Sprint 20, 2026-09-27)
- **API:** `VersionedSchema` (`SchemaV1` 1.0.0, `SchemaV2` 2.0.0), `SchemaMigrationPlan` (`HouseholdMigrationPlan`)
  with one `MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`, passed to
  `ModelContainer(for:migrationPlan:configurations:)` by the single factory. iOS 17+; project floor iOS 26, Xcode 27.
- **Change:** `TransactionRecord` gains one optional stored property, `refundOfTransactionID: UUID?`. Adding an
  optional attribute is a lightweight migration: existing rows get nil; nothing is renamed, retyped or dropped.
- **How the V1 hash is kept:** `SchemaV1.TransactionRecord` is a frozen copy (stored properties and attributes only)
  of the class installed on the owner's iPhone at `063a510`, checked against that commit with git (no persistence file
  changed between `063a510` and the Sprint 20 plan; `versionIdentifier` was 1.0.0). The eleven unchanged models are
  the same classes in both schemas; their entity hashes are equal and `TransactionRecord`'s differ, so the two
  versions' checksums are distinct.
- **Evidence:** `PersistenceTests.aSchemaV1StoreOnDiskMigratesToSchemaV2WithEveryRecord` writes one row of every
  model through SchemaV1 to a store on disk, opens it through the app's factory and plan, and reads every row back.
- **Fallback:** if a store ever failed to open, the app shows `StoreUnavailableView` and deletes nothing. The owner
  makes a backup (Settings › Data › Back up now) before installing a build with a new schema version; a restore
  into a fresh install is the way back.
- **Rule from here:** every stored change is a new version: freeze the current class as `SchemaVn.<Model>` (stored
  properties only), add the next version and a stage, and extend the on-disk migration test.

## SwiftData schema versioning — SchemaV2 → SchemaV3 (Sprint 22, 2026-09-28)
- **API:** the same as SchemaV2: `VersionedSchema` `SchemaV3` 3.0.0 added to `HouseholdMigrationPlan.schemas`
  (`[SchemaV1, SchemaV2, SchemaV3]`) with a second stage, `MigrationStage.lightweight(fromVersion: SchemaV2.self,
  toVersion: SchemaV3.self)`. `CurrentSchema` is SchemaV3. iOS 17+; project floor iOS 26, Xcode 27.
- **Change:** `RecurringTransaction` gains one optional stored property, `kindRawValue: String?` (a `RecurringKind`
  raw value; nil means a bill). Adding an optional attribute is a lightweight migration: every existing series gets
  nil and reads as a bill; nothing is renamed, retyped or dropped. The service stores a bill as nil too, so a backup
  of bills carries no kind.
- **How the V1 and V2 hashes are kept:** SchemaV2 was installed on the owner's iPhone at `fd7e67e`, so it is frozen
  like SchemaV1. `SchemaV1.RecurringTransaction` (`Persistence/Models/V1/RecurringTransactionV1.swift`) is a frozen
  copy of the class installed at `063a510`, which SchemaV2 shared unchanged; its `@Model` body (stored properties,
  attributes, init) was checked line for line against `git show 063a510:` of the old model file. SchemaV1 and
  SchemaV2 list that class by its qualified name; SchemaV3 lists `SchemaV3.RecurringTransaction`,
  `SchemaV2.TransactionRecord` and the ten SchemaV1 classes, so only `RecurringTransaction`'s entity hash differs
  from V2 and the checksums stay distinct.
- **Evidence:** `PersistenceTests.aSchemaV2StoreOnDiskMigratesToSchemaV3WithEveryRecord` writes one row of every
  model (two series, a refund link) through SchemaV2 to a store on disk, opens it through the app's factory and
  plan, reads every row back and checks every series is a bill;
  `aSchemaV1StoreOnDiskMigratesToTheCurrentSchemaWithEveryRecord` runs a V1 store through both stages. Backup format
  v4 carries the kind (v1 to v3 files still read, every series a bill; an older file naming a kind is refused).
- **Fallback:** as for SchemaV2: `StoreUnavailableView`, nothing deleted; a backup before installing the build.

## SwiftData schema versioning — SchemaV3 → SchemaV4 (Sprint 23, 2026-09-28)
- **API:** the same as SchemaV3: `VersionedSchema` `SchemaV4` 4.0.0 added to `HouseholdMigrationPlan.schemas`
  (`[SchemaV1, SchemaV2, SchemaV3, SchemaV4]`) with a third stage, `MigrationStage.lightweight(fromVersion:
  SchemaV3.self, toVersion: SchemaV4.self)`. `CurrentSchema` is SchemaV4. iOS 17+; project floor iOS 26, Xcode 27.
- **Change:** `TransactionRecord` gains one optional stored property, `splitGroupID: UUID?` (shared by the parts of
  one split payment; nil = not split). Adding an optional attribute is a lightweight migration: every existing record
  gets nil; nothing is renamed, retyped or dropped.
- **How the V1–V3 hashes are kept:** SchemaV3 was installed on the owner's iPhone at `8a9ec36`, so it is frozen like
  SchemaV1 and SchemaV2. `SchemaV2.TransactionRecord` (`Persistence/Models/V1/TransactionRecordV2.swift`) is a frozen
  copy of the class installed at `fd7e67e` and shared unchanged by SchemaV3; its `@Model` body (stored properties,
  attributes, init) was checked line for line against `git show 8a9ec36:` of the old model file (the file had not
  changed since `fd7e67e`). SchemaV2 and SchemaV3 still list that class; SchemaV4 lists `SchemaV4.TransactionRecord`,
  `SchemaV3.RecurringTransaction` and the ten SchemaV1 classes, so only `TransactionRecord`'s entity hash differs
  from V3 and the checksums stay distinct. `FrozenSchemaTests` is unchanged.
- **Evidence:** `PersistenceTests.aSchemaV3StoreOnDiskMigratesToSchemaV4WithEveryRecord` writes one row of every
  model (a refund link, a recurring occurrence, a purchase series, a task link) through SchemaV3 to a store on disk,
  opens it through the app's factory and plan, reads every row back and checks nothing is split;
  `aSchemaV1StoreOnDiskMigratesToTheCurrentSchemaWithEveryRecord` runs a V1 store through all three stages. Backup
  format v5 carries the group (v1 to v4 files still read, nothing split; an older file with a group is refused).
- **Fallback:** as for SchemaV2: `StoreUnavailableView`, nothing deleted; a backup before installing the build.

## TipKit — contextual tips (Sprint 24, 2026-09-28)
- **API:** `import TipKit` (system framework, no extra `project.yml` entry needed, same as `Charts`). `Tip` is a
  plain protocol (`id: String`, `title: Text`, `message: Text?`, `image: Image?`, `rules: [Rule]`,
  `options: [any Option]`); most members have default implementations, so a tip needs only `title`/`message` (we add
  an explicit `id` for stability and for the unit test). `Tips.configure([.displayFrequency(.immediate)])` loads the
  datastore once at app start (`applicationDefault` datastore location, i.e. no App Group). `.popoverTip(_:)` and
  `TipView(_:)` render a tip; `#Rule(expression) { … }` with a `static let event = Tips.Event(id:)` and
  `$0.donations.count >= N` gates a tip on how many times something happened; `Tips.Event.donate()` is `async`,
  non-throwing. `Tips.resetDatastore()` and `Tips.configure(_:)` both `throws`; a reset only takes effect for tips
  configured again afterward, so we reset before configuring, never after. `Tips.showAllTipsForTesting()` /
  `hideAllTipsForTesting()` are iOS 17+, same floor as the rest of TipKit — no extra availability check needed.
  Minimum OS: iOS 17.0; project floor iOS 26, so no `#available` gate is needed anywhere in this codebase. No
  entitlement, no paid membership, works under a free Personal Team (spec §11.2).
- **iOS 26 pitfalls (community reports, not yet in Apple's own docs) — verify again after each Xcode/iOS update:**
  1. A `popoverTip` can reappear on every tab switch instead of showing once (Apple Developer Forums thread 805796,
     Feedback FB20904972). Mitigation: every Sprint 24 tip sets `options: [MaxDisplayCount(1)]`.
  2. A `popoverTip` on a toolbar `Button` with no explicit `buttonStyle` can fail to show. Mitigation: `Select`
     (`BudgetView`, Bulk select tip) gets an explicit `.buttonStyle(.plain)`; `.bottomBar` placement is avoided for
     every tipped control.
  3. iOS 26.1: `popoverTip` reportedly does not show on a toolbar `Menu` button. Mitigation: the Saved searches tip is
     not attached to Budget's filter `Menu`; it is an inline `TipView` in the More filters sheet instead (reached
     from the same menu, and where a search worth saving has usually just been built).
- **Fallback:** every tip is a plain, dismissible popover or inline card; none of the 10 features it documents
  depends on the tip appearing. If TipKit fails silently (`try?` on `configure`/`resetDatastore`), the feature itself
  still works; only the hint is missing.
- **Decision:** ship with the mitigations above rather than waiting on an Apple fix; re-check this section against
  the release-note history the next time Xcode or the iOS SDK version changes.
