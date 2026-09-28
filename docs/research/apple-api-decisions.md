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

## First-run tutorial: TipKit vs. custom spotlight tour — Sprint 24, 2026-09-28
Verified against Apple's official documentation (JSON API behind developer.apple.com, fetched directly since the
rendered pages are JS-only) and current Apple Developer Forums threads for known regressions. Every declaration
below is quoted from the live doc, not from memory.

### TipKit — current API shape (framework `TipKit`)
- **`Tip`**: `protocol Tip : Identifiable, Sendable` — iOS 17.0+
  (developer.apple.com/documentation/tipkit/tip). So `Tip` **is** `Sendable`; a conforming type must itself be
  `Sendable` under Swift 6 strict concurrency (a plain `struct` with `Text`/`Image`/`String` properties is fine —
  `Text` and `Image` are `Sendable`). Required: `title: Text`; optional with defaults: `message: Text?`,
  `image: Image?`, `rules: [Rule]` (`@Tips.RuleBuilder`, iOS 17+, doc …/tipkit/tip/rules), `options: [TipOption]`,
  `actions: [TipAction]`, `id` (default from `Self`'s name). `Tip.Rule` is a `typealias` for `Tips.Rule`, built with
  the `#Rule` macro over a `Tips.Event` or a `Tips.Parameter<Value>` (`Value: Codable & Sendable`) — both iOS 17+
  (…/tipkit/tips/parameter, …/tipkit/tips/event).
- **`Tips` namespace**: `@frozen enum Tips`, iOS 17.0+ (…/tipkit/tips).
  - `static func configure(_ configuration: [Tips.ConfigurationOption] = []) throws` — iOS 17.0+
    (…/tipkit/tips/configure(_:)). Call once per app launch (Apple's own sample calls it from `App.init()`).
  - `static func resetDatastore() throws` — iOS 17.0+ (…/tipkit/tips/resetdatastore()): "Resets the tips' datastore
    to the initial state for re-testing tip display rules and eligibility." Must run **before** `configure()`.
  - `static func showAllTipsForTesting()` / `static func hideAllTipsForTesting()` — **both iOS 17.0+**, not 18+ as
    early web summaries claim (…/tipkit/tips/showalltipsfortesting(), …/tipkit/tips/hidealltipsfortesting()).
  - `Tips.ConfigurationOption.datastoreLocation(_:)` — iOS 17.0+; default is `.applicationDefault` (Application
    Support on iOS/macOS/watchOS/visionOS, `UserDefaults` on tvOS). **No App Groups or entitlement needed** for the
    default location — `.groupContainer(identifier:)` exists only if you deliberately opt into a shared container,
    which this project does not (zero-cost constraint, §2). `.displayFrequency(_:)` throttles how often *new* tips
    appear app-wide (default `.daily`); a tip can opt out per-tip with the `IgnoresDisplayFrequency` option.
  - `Tip.Option` (`= TipOption`): `MaxDisplayCount(_:)` (iOS 17.0+, invalidates after N displays, default
    unlimited), `MaxDisplayDuration(_:)` (**iOS 18.0+**, cumulative on-screen time, 60 s minimum before
    auto-invalidation), `IgnoresDisplayFrequency(true)` (iOS 17.0+, default false).
- **`TipView<Content>`**: `@MainActor @preconcurrency struct TipView<Content> where Content: Tip` — iOS 17.0+
  (…/tipkit/tipview). Inline card; the surrounding layout reflows to fit it. Apple's own guidance: "Use this style
  of tip whenever possible to avoid covering UI elements."
- **`.popoverTip(_:arrowEdge:action:)`**: `@preconcurrency nonisolated func popoverTip(_ tip: (any Tip)?, arrowEdge:
  Edge? = nil, action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) -> some View` — iOS 17.0+
  (…/swiftui/view/popovertip(_:arrowedge:action:)). Presents as a system popover anchored to the modified view when
  the tip becomes eligible.
- **`TipGroup`**: `final class TipGroup`, **iOS 18.0+** (…/tipkit/tipgroup — this is the one clearly new-since-17
  type). `init(_ priority: TipGroup.Priority = .firstAvailable, @Tips.GroupBuilder _ builder: () -> [any Tip])`;
  `Priority` is `.ordered` (show tips in listed order, one at a time) or `.firstAvailable` (show whichever's rules
  are met first); `@MainActor final var currentTip: (any Tip)?` and `currentTipUpdates` (an `AsyncSequence`) expose
  the tip currently due. No built-in numbering ("step 3 of 6") — the app must count `currentTip`'s index itself if
  it wants a step count.
- **Swift 6 concurrency**: `Tip` conforms to `Sendable`, and `TipView`/`popoverTip`'s closures are pinned
  `@MainActor @Sendable`, so both are safe to use from `@MainActor` SwiftUI code without extra annotations.
  `Tips.Parameter<Value>`'s `Value` must be `Codable & Sendable`; a `@Tips.Parameter static var` on a `Tip` type is
  a plain stored static that TipKit itself observes for rule re-evaluation — no actor-isolation conflict was found
  in the docs, but a static `Parameter` on a non-`Sendable` value type would not compile, which the required
  `Value: Sendable` constraint already prevents.
- **UI test launch pattern** (not literal doc text, but built directly on the two testing APIs above, both stable
  since iOS 17): in `App.init()`, branch on `ProcessInfo.processInfo.arguments` before `Tips.configure()`:
  `-uiTestingShowAllTips` → `try? Tips.resetDatastore()` then `Tips.showAllTipsForTesting()` before `configure()`;
  `-uiTestingHideAllTips` → `Tips.hideAllTipsForTesting()` before `configure()`. Both calls are synchronous and
  process-wide, so a single flag per XCUITest launch is enough; no datastore file needs to be seeded from the host.
- **Known pitfalls (Apple Developer Forums, live at research time, cited because they are unresolved regressions
  the docs do not mention):**
  - **iOS 26 tab-switch regression**: a `popoverTip` can re-appear every time the user switches `TabView` tabs
    instead of once (forums thread 805796; DTS engineer acknowledged a possible regression, filed as FB20904972).
    Workaround in the thread: set `MaxDisplayCount(1)` so the tip cannot show a second time regardless of the
    replay bug. Relevant to us because the tour's own tips must not spam every tab switch.
  - **Toolbar items**: a `popoverTip` on a bare `Button` inside `ToolbarItem` frequently fails to appear at all
    (forums thread 735961). Workarounds that reporters confirm work: give the button an explicit `.buttonStyle(...)`
    before `.popoverTip(...)`, or attach `.popoverTip(...)` to the inner `Label`/`Image` rather than the `Button`
    itself, or pass an explicit `arrowEdge:`. `ToolbarItemPlacement.bottomBar` is reported as unreliable regardless
    of workaround — avoid it for a tip anchor.
  - **iOS 26.1 toolbar *menu* buttons**: `popoverTip` reported not displaying at all on a `Menu` placed in a
    toolbar (forums thread 804587); no confirmed workaround yet — avoid anchoring a tip to a toolbar `Menu`.
  - **Sheets**: not independently verified here; treat a tip anchored to content presented in a `.sheet` as
    unverified until it is exercised in this app's own UI tests (§18 "record remaining uncertainty").

### Spotlight/coach-mark tour — pure SwiftUI technique (no packages)
All APIs below are confirmed on developer.apple.com; the tour composition itself is this project's design, not an
Apple recipe.
- **Capturing a target's frame across the app**: `nonisolated func anchorPreference<A, K>(key: K.Type = K.self,
  value: Anchor<A>.Source, transform: @escaping (Anchor<A>) -> K.Value) -> some View where K: PreferenceKey` — iOS
  13.0+ (…/swiftui/view/anchorpreference(key:value:transform:)). Each spotlighted control tags itself with
  `.anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { [stopID: $0] }`; a single
  `.overlayPreferenceValue(_:_:)` (iOS 13.0+, …/swiftui/view/overlaypreferencevalue(_:_:)) placed high in the view
  tree (e.g. on the root `TabView`/`NavigationStack`) collects the dictionary of anchors and resolves the current
  stop's `Anchor<CGRect>` into that overlay's own coordinate space with a `GeometryProxy` subscript
  (`proxy[anchor]`), which is what lets the cut-out track the control regardless of which screen or nested
  `NavigationStack` it lives in. `matchedGeometryEffect` (iOS 14.0+) is the wrong tool here: it animates one view's
  own geometry to match another view's, it does not report a frame to an ancestor, so it cannot feed a spotlight
  cut-out computed in an overlay.
  - **Toolbar items**: `anchorPreference` works normally on a view placed inside `ToolbarItem`'s content closure,
    because that content is still an ordinary SwiftUI view (mind the popoverTip toolbar pitfalls above only if the
    stop *also* uses a Tip there; the tour's own preference-based highlight does not depend on TipKit).
  - **Tab bar items**: **do not** try to anchor a cut-out to an individual tab bar button. Apple's own `TabView`
    renders the bar chrome itself (including the iOS 26 liquid-glass tab bar); the tab labels declared inside
    `TabView`/`Tab` are configuration data, not SwiftUI views in the app's own hierarchy, so no modifier (including
    `anchorPreference`) attaches to one. For any tour stop about a tab, either (a) skip the literal cut-out and show
    a bottom-anchored callout with an arrow that visually points at the tab bar without a precise per-icon hole, or
    (b) approximate the icon's rect from the tab bar's own frame (captured once via `anchorPreference` on the
    `TabView` itself) divided evenly by tab count — a documented approximation, not an Apple-provided anchor, and
    it breaks if Dynamic Type or an iPad regular-width sidebar changes the bar's layout, so it needs a fallback to
    (a) when the computed rect looks wrong (e.g. outside the tab bar's own bounds).
- **Dimming with a cut-out**: build the dim layer as `Color.black.opacity(0.55)` sized to the full screen, and mask
  it with a `Path` that adds the full rect plus a rounded-rect subtraction at the target frame using the even-odd
  fill rule (`Path.fill(style: FillStyle(eoFill: true))`) via `.mask(alignment:_:)` (iOS 15.0+,
  …/swiftui/view/mask(alignment:_:)). Equivalently, layer two rectangles and blend them with
  `.compositingGroup()` (iOS 13.0+, …/swiftui/view/compositinggroup()) followed by `.blendMode(.destinationOut)`
  (`BlendMode.destinationOut`, iOS 13.0+, …/swiftui/blendmode/destinationout) on the cut-out shape so it erases the
  dim layer beneath it; `compositingGroup()` is required before `blendMode` or the blend applies against the whole
  window instead of just the dim layer. Either technique is placed in a full-screen `overlay`/`ZStack` above the
  `TabView`, driven by the anchor collected above, so it sits above tab content and the tab bar alike.
- **Reduce Motion**: read `@Environment(\.accessibilityReduceMotion)` (`EnvironmentValues.accessibilityReduceMotion:
  Bool`, iOS 13.0+) and skip the cross-fade/move animation between stops when it is true — cut directly to the next
  cut-out and callout position instead of animating the mask or repositioning.
- **VoiceOver focus and modality**: give the callout card a stable identity and pull VoiceOver to it with
  `@AccessibilityFocusState` (`AccessibilityFocusState<Value>`, iOS 15.0+,
  …/swiftui/accessibilityfocusstate) bound via `.accessibilityFocused($focus, equals: stopID)`, set right after the
  stop appears (and again after Reduce Motion's instant transition). Mark the callout `.accessibilityAddTraits(.isModal)`
  (`accessibilityAddTraits(_:)`, iOS 14.0+, …/swiftui/view/accessibilityaddtraits(_:); `.isModal`,
  `AccessibilityTraits.isModal`, iOS 13.0+, …/swiftui/accessibilitytraits/ismodal) so VoiceOver's swipe navigation
  stays confined to the tour overlay instead of leaking into the dimmed app content underneath. Announce each new
  stop explicitly with `AccessibilityNotification.Announcement("Step \(n) of \(total): \(title)").post()`
  (`struct Announcement`, iOS 17.0+, developer.apple.com/documentation/accessibility/accessibilitynotification/announcement)
  fired when the stop changes, since a modal region appearing does not always generate its own VoiceOver
  announcement.
- **Step count / Next / Skip**: plain SwiftUI state (`@Observable` tour model holding `stops: [Stop]` and
  `currentIndex`), not an Apple API — "Step \(currentIndex + 1) of \(stops.count)" as both visible text and the
  accessibility announcement above.

### Recommendation: custom spotlight overlay for (a), TipKit only for (b)
- **Use a custom `anchorPreference`/mask overlay for the 5–7 stop spotlight tour, not TipKit.** TipKit has no
  concept of dimming the rest of the screen, no built-in cut-out/spotlight visual, no numbered step count, and (per
  `TipGroup`'s own doc) presents its tips as ordinary popovers/inline cards — a `TipGroup` can sequence tips, but it
  cannot black out the rest of the screen around them, and per the tab-bar limitation above it cannot anchor cleanly
  to a tab bar item either. Reusing it would mean fighting the framework for the one visual effect ((a)) explicitly
  asks for, while the pieces the tour actually needs — anchor capture, masking, focus, Reduce Motion, VoiceOver
  modality — are all plain, stable SwiftUI/Accessibility APIs already used elsewhere in this app.
- **Use TipKit as specified for (b), the contextual tips**, exactly because that is what it is built for: per-
  feature `Tip`s with `#Rule`-based eligibility (e.g. a `Tips.Event` donated the first time a deeper screen is
  reached), `TipView` inline where a feature can be highlighted without covering controls, `.popoverTip` where it
  must point at a specific control (respecting the toolbar/tab-switch pitfalls above), and `Tips.resetDatastore()`
  wired to Settings' "Reset tips" action.
- **Settings replay (c)**: "Show the tour again" simply resets and restarts the custom tour's own state (no TipKit
  involvement — the tour never used TipKit's datastore). "Reset tips" calls `Tips.resetDatastore()` followed by
  `Tips.configure()` so contextual tips can reappear, matching Apple's own sample pattern of calling `configure()`
  once per session after any datastore reset.
- **Fallback / zero-cost check**: both mechanisms are pure on-device SwiftUI/TipKit state — no entitlement, no App
  Groups, no paid membership, works under a free Personal Team and in the Simulator. TipKit's default datastore
  location needs nothing beyond the app's own sandbox.
- **Unverified / left for CI and the walk**: the exact visual quality of the tab-bar approximation in (2) above,
  the iOS 26 tab-switch popoverTip regression's real-world impact on this app's own tips (mitigate with
  `MaxDisplayCount(1)` from the start rather than waiting to hit it), and whether the modal VoiceOver region
  correctly blocks interaction with dimmed controls in the Simulator's accessibility inspector (record in
  `docs/research/open-questions.md` if the Phase 10 accessibility audit finds it does not).

## App Intents / Siri / Apple Intelligence on iOS 26 — Sprint 25 research, 2026-09-28
Scope: whether/how to add Siri phrases for wishlist and task-board actions and a spoken "Add headphones for 149 to
my wishlist" utterance, and whether anything needs a paid account. Apple docs consulted via
developer.apple.com/documentation/appintents (the DocC JSON endpoint, `.../tutorials/data/documentation/...json`,
was used to read exact platform/version metadata) and the cited WWDC session pages. No blog is used as a fact
source below; two are cited only to corroborate reading of an official page (marked "interpretation").

**1a. `AppShortcutsProvider` phrases and parameters**
- A phrase is built from fixed text plus, optionally, `\(.applicationName)` and **`AppEntity`/`AppEnum`
  parameters only** — never a `String`, numeric, or other free-form parameter embedded in the phrase text. Source:
  https://developer.apple.com/documentation/appintents/appshortcut and
  https://developer.apple.com/documentation/appintents/app-shortcuts (App Shortcuts article), corroborated by
  https://developer.apple.com/videos/play/wwdc2023/10102/ ("Spotlight your app with App Shortcuts", the session that
  introduces phrase parameters) and the WWDC25 example in
  https://developer.apple.com/videos/play/wwdc2025/244/ ("Get to know App Intents"), which shows
  `"Navigate to \(\.$navigationOption) in \(.applicationName)"` with `navigationOption` typed as an `AppEnum`.
  `AppEntity`/`AppEnum` also gained a synonyms addition to `DisplayRepresentation` at WWDC25 so a phrase parameter's
  spoken values can have extra synonyms — still enumerated values, not free text.
  `AppShortcutsProvider`, `AppShortcut`: iOS 16.0+ (unchanged in 26); no entitlement.
- The app's own `LogTransactionIntent` already relies on the one condition this implies: its `text: String`
  parameter is **not** in the phrase (`"Log a transaction in \(.applicationName)"` has no embedded parameter), so
  Siri asks for it afterwards via `requestValueDialog` rather than trying to parse it out of the trigger phrase.
  This is the documented pattern for any parameter that is not an `AppEntity`/`AppEnum`.

**1b. "Add headphones for 149 to my wishlist in Household Hub" — what Siri can capture in one utterance**
- Because a phrase parameter must be an `AppEntity`/`AppEnum`, **neither the item name ("headphones") nor the
  amount (149) can be declared as an embedded phrase parameter** — an `AppEntity`/`AppEnum` is a predefined,
  finite set of values (categories, accounts, columns), not open text or a decimal typed at speech time. There is
  no documented, supported way to have Siri capture a specific free-text word and a specific number out of one
  utterance for a custom (non-`@AssistantIntent`) intent; that is not what App Shortcuts parameters are for.
  Source: same App Shortcuts pages above; also `requestValue(_:)`
  (https://developer.apple.com/documentation/appintents/intentparametercontext/requestvalue(_:)) exists precisely
  because App Intents expects most parameters to be filled by a follow-up turn, not by NL-parsing the trigger
  phrase.
- The only documented and already-proven way to get this whole sentence in one breath is the pattern
  `LogTransactionIntent` already uses: a **fixed phrase with no embedded parameter** ("Add to my wishlist in
  Household Hub") whose single `@Parameter var text: String` has a `requestValueDialog`; Siri asks for it once if
  the person only said the trigger phrase, but if the person appends the rest in the same utterance ("Add to my
  wishlist in Household Hub, headphones for 149") the spoken remainder is delivered as that parameter's value
  without a follow-up turn, because it is App Intents filling one already-declared `String` parameter, not Siri
  parsing a wishlist item + a price out of the phrase. The **app's own text** then parses "headphones for 149"
  (name + amount), the same job `ShortcutEntry.draft` already does for `LogTransactionIntent`'s Quick Add grammar
  (`HouseholdHubApp/App/AppIntents.swift`). A wishlist add would need its own small grammar (or reuse of the
  Quick Add money parser) for "<name> for <amount>", plus a confirmation dialog before saving (§8.1: a wishlist
  purchase is a data-safety change, so a *creation* draft should still be confirmed, matching
  `requestConfirmation` already used for money in `LogTransactionIntent`).
- A follow-up prompt (`requestValue`) is only reachable this way if the person leaves out the free-text part
  entirely; Apple does not document a way to make Siri ask two separate follow-up questions (one for the item name,
  one for the price) out of a single `String` parameter — that split has to happen in the app's own parser after
  the one dictated string comes back, exactly as today.

**1c. `AppEntity` + `EntityQuery` for categories, accounts, wishlist items, task columns**
- `AppEntity` (a Siri/Shortcuts-visible, identifiable, `DisplayRepresentation`-able concept) and `EntityQuery`
  (`entities(for:)` to resolve by ID, `suggestedEntities()` for a default list; `EntityStringQuery` adds
  `entities(matching:)` for typed/spoken search) are both iOS 16.0+, no entitlement. Sources:
  https://developer.apple.com/documentation/appintents/appentity,
  https://developer.apple.com/documentation/appintents/entityquery,
  https://developer.apple.com/documentation/appintents/entitystringquery.
- Fit for this app: `CategoryRecord`, the transaction `Account`/wallet concept, wishlist items, and Kanban columns
  are all small, enumerable, identifiable domain objects already backed by SwiftData — a natural `AppEntity` +
  `EntityQuery` per type (queried through the existing services, never a raw `ModelContext`, per CLAUDE.md §4).
  These would be used as **disambiguation/selection parameters** in future intents (e.g. "Move task to Done in
  Household Hub" with `column` as an `AppEntity` phrase parameter, or a category picker inside a
  `requestDisambiguation` step) — not as a way to smuggle free text into a phrase.

**1d. `requestConfirmation` for money**
- `AppIntent.requestConfirmation(actionName:dialog:)` (and its `conditions:`/`content:` overloads) shows the person
  a system confirmation (voice + on-screen) before `perform()` continues; `LogTransactionIntent` already calls it
  before writing a transaction. The overload list was confirmed via WebSearch against
  https://developer.apple.com/documentation/AppIntents/AppIntent/requestConfirmation(conditions:actionName:dialog:)
  and sibling pages (the individual overload page did not render through the docs JSON endpoint used elsewhere in
  this research, so this fact is corroborated by the overload's canonical URL plus the parent
  https://developer.apple.com/documentation/appintents/appintent page rather than a captured JSON body — flagged
  as the one fact in this section with weaker sourcing). iOS 16.0+, no entitlement. Same call should gate a
  wishlist-add's amount and a "delete task"/"delete transaction" intent if one is ever added, per CLAUDE.md §5
  ("never silently delete financial history").

**1e. Opening the app vs. running in the background**
- `IntentModes`/`AppIntent.supportedModes` is **iOS 26.0+** exactly — introduced with this app's deployment target,
  not before. Source: https://developer.apple.com/documentation/appintents/intentmodes and
  https://developer.apple.com/documentation/appintents/appintent/supportedmodes (platform metadata read via the
  docs JSON endpoint: `iOS 26.0` on both pages, not beta). `OpenQuickAddIntent` uses `.foreground(.immediate)`
  (must open the app), `LogTransactionIntent` uses `.background` (never opens the app; the dialog/confirmation is
  spoken, and the transaction is written entirely off-screen). A wishlist-add and a task-add intent should also be
  `.background` — a person adding an item to a list by voice does not expect the app to jump to the foreground —
  while an intent that needs to show a screen (e.g. "open the wishlist") stays `.foreground`. No entitlement either
  way; this is a runtime behavior flag, not a capability.

**1f. Localized phrases — `AppShortcuts.xcstrings`**
- The App Shortcuts phrase strings must live in a String Catalog file **named exactly `AppShortcuts.xcstrings`**
  in the app target (not `Localizable.xcstrings`) for the system to localize trigger phrases per-language;
  confirmed by interpretation of Apple's WWDC23 String Catalogs session
  (https://developer.apple.com/videos/play/wwdc2023/10155/, "Discover String Catalogs") plus the naming convention
  documented on `AppShortcutPhrase`
  (https://developer.apple.com/documentation/appintents/appshortcutphrase) — the exact "must be named
  AppShortcuts.xcstrings" phrasing was read from a developer's write-up
  (https://sowenjub.me/writes/localizing-app-shortcuts-with-app-intents/, interpretation only) and matches what is
  already in this repo. **This file already exists**: `HouseholdHubApp/Resources/AppShortcuts.xcstrings`, source
  language `en`, currently holding the two existing phrases ("Log a transaction in ${applicationName}", "Quick Add
  in ${applicationName}"). New phrases (wishlist add, task add) need entries added here, and Spanish entries per
  Sprint 25's plan — this is ordinary String Catalog editing, not a new capability.

**2a. App Intent domains / assistant schemas — is there a finance/list/task schema?**
- `AssistantSchemas` (the enum Apple ships the fixed domain contracts under; supersedes the older
  `AssistantIntent`/`AssistantEntity`/`AssistantSchema` types, which the page itself lists as "Previous schema
  types") was read directly from
  https://developer.apple.com/tutorials/data/documentation/appintents/assistantschemas.json (DocC JSON for
  https://developer.apple.com/documentation/appintents/assistantschemas) to get the exhaustive protocol list rather
  than trust a rendered summary. The listed domains are: **Books, Browser, Camera, Files, Journal, Mail, Photos,
  Presentation, Reader, Spreadsheet, System, VisualIntelligence, Whiteboard, WordProcessor.**
- **There is no schema for finance, budgeting, expenses, to-do lists, tasks, reminders, or Kanban boards.** A
  household budget/wishlist/task app has no `@AssistantIntent(schema:)`/`@AssistantEntity(schema:)` domain to
  conform to; every intent this app ships is (and, for the foreseeable iOS 26 timeframe, must remain) a plain
  custom `AppIntent` exposed only through its own `AppShortcutsProvider`, not through one of Apple's fixed
  cross-app domains. `AssistantIntent(schema:)`: iOS 16.0+ per its own page
  (https://developer.apple.com/documentation/appintents/assistantintent(schema:)), but that only matters for the
  fourteen domains above.

**2b. Siri's on-screen awareness / personal context**
- On-screen entity awareness ("people can ask Siri/ChatGPT about content visible on screen", `NSUserActivity`
  entity association, and a newer "View Annotations API") is described in WWDC25's
  https://developer.apple.com/videos/play/wwdc2025/275/ ("Explore new advances in App Intents") and
  https://developer.apple.com/documentation/appintents/making-onscreen-content-available-to-siri-and-apple-intelligence
  (page title/topic confirmed by search; the DocC JSON endpoint 404s for this particular article page, so its
  exact "introduced at" platform number could not be read the same way as the API references above — recorded as
  an open question below rather than guessed). The View Annotations API is discussed again a year later at
  WWDC26 (https://developer.apple.com/videos/play/wwdc2026/343/, "Explore advanced App Intents features for Siri
  and Apple Intelligence", and https://developer.apple.com/videos/play/wwdc2026/240/, "Build intelligent Siri
  experiences with App Schemas") — i.e. **this is a live, still-evolving area (WWDC26 already shipped its own
  session on it, months after iOS 26's release), not a single one-time iOS 26.0 feature**, and this project's
  floor is iOS 26 exactly. **Recommendation: treat on-screen awareness as shipped-but-still-growing; adopt only
  the entity/`AppEntity` + `EntityQuery` plumbing already planned for 1c (which is what feeds it) and do not chase
  the newer WWDC26 View Annotations API surface until the toolchain/OS floor is checked against it — flagged as an
  open question below.**

**2c. Free-form speech ("I spent 40 on groceries at Safeway yesterday") to structured parameters**
- Apple's documented mechanism for a spoken sentence to become structured intent parameters is: (a) the fourteen
  fixed `AssistantSchemas` domains, none of which fit finance (see 2a), or (b) a single free-text `String`/decimal
  parameter that the **app itself** parses after Siri hands it over as one dictated value (1b above). There is no
  documented API by which a third-party, non-schema app intent gets Apple Intelligence to split an arbitrary
  sentence into named parameters (amount, merchant, date) before `perform()` runs. **This app must keep doing what
  it already does**: one free-text parameter in, its own deterministic grammar (`ShortcutEntry`, §25) — or, per
  CLAUDE.md §6, the on-device Foundation Models parser — out.

**2d. Foundation Models framework as an in-intent fallback parser**
- `FoundationModels` (the on-device ~3B-parameter language model framework backing Apple Intelligence) is
  **iOS 26.0+ exactly**, confirmed via
  https://developer.apple.com/tutorials/data/documentation/foundationmodels.json (platform metadata: iOS 26.0,
  not beta). No entitlement beyond the framework import; it only produces output when Apple Intelligence is
  enabled and the device supports it (A17 Pro/M-series or newer — a device/runtime condition, not an entitlement,
  so `SystemLanguageModel.availability` must be checked at call time with a deterministic fallback, per CLAUDE.md
  §6). Nothing here changes the app's existing rule: **Foundation Models only refines/interprets a draft; it never
  writes to SwiftData, and there is no cloud fallback.** Using it inside an intent's `perform()` to turn a dictated
  wishlist sentence into a name+amount draft — still shown back to the person via `requestConfirmation` before the
  transaction/wishlist row is created — is consistent with §6 and does not need anything beyond what 1b already
  requires.

**3. Entitlements and free Personal Team**
- **No entitlement file exists in this repo** (`find . -iname "*.entitlements"` is empty), and the app already
  ships two working App Shortcuts (`LogTransactionIntent`, `OpenQuickAddIntent`) with no entitlement added for
  them — consistent with `AppShortcutsProvider`/`AppShortcut`/`AppEntity`/`EntityQuery`/`AppIntent` all being
  plain Swift-framework APIs (iOS 16.0+) that need no capability toggle in Xcode's Signing & Capabilities and no
  provisioning-profile entry. The `com.apple.developer.siri` entitlement that shows up in older material is a
  **SiriKit** (the pre-iOS 16, `INIntent`-based framework) requirement, not an App Intents one; this app uses only
  App Intents. **No paid Apple Developer Program is needed for any of §1 or §2's App Intents/App Shortcuts/
  Foundation Models work**, and none of it needs App Groups (out of scope per CLAUDE.md §2 regardless).
- **App Shortcuts on a free-team Simulator/device build**: the App Shortcuts phrases, Spotlight surfacing, and
  Shortcuts-app entries are a function of the app being installed and `AppShortcutsProvider.appShortcuts` being
  read at launch — nothing here is gated behind provisioning. This matches the "Today (baseline)" note in
  `docs/sprints/SPRINT-25.md` that the two existing intents already work. **Open question for the owner (recorded
  below): has "Log a transaction in Household Hub" actually been tried by voice on the owner's free-Personal-Team
  device build, or only through the Shortcuts app?** — Siri itself (vs. the Shortcuts app) sometimes needs the
  device's own Siri/dictation to be enabled, which is a device setting, not a signing capability, but is worth the
  owner confirming since Siri cannot run in CI.

**4. Testing**
- **Unit-testable (CI, Swift Testing, per CLAUDE.md §8):** everything an intent's `perform()` delegates to a
  service — `ShortcutEntry.draft`/a new wishlist-add grammar's parsing, `TransactionService`/a `WishlistService`
  write path, the lock-check branch (`isLockEnabled`), and the `Failure` cases' mapping — exactly as
  `LogTransactionIntent`'s logic is already tested indirectly through `ShortcutEntry` and the transaction service,
  never through `AppIntent.perform()` itself (the Siri/App Intents runtime cannot run headlessly in CI or the
  Simulator — there is no documented API to invoke an `AppIntent` end-to-end in an XCTest/Swift Testing target the
  way `perform()` would really run under Siri).
- **Hand-check only, on a real device (WALK-QUEUE, cannot run in CI):** the actual phrases spoken to Siri
  (including in Spanish once localized), `requestValueDialog`/`requestValue` follow-up turns, `requestConfirmation`
  wording and the Face ID/passcode prompt it triggers when the lock is on, whether Siri actually offers the
  shortcut after first launch (donation/Spotlight surfacing timing is not deterministic), and the exact behavior
  described in 1b (whether a person's one-breath "trigger phrase + free text" utterance is delivered as a single
  parameter value the way `LogTransactionIntent` already assumes it is) — this last one is the load-bearing
  assumption the whole "one sentence" plan rests on and should be the first thing checked on the phone before
  building a wishlist grammar around it.

**Open questions → recorded in `docs/research/open-questions.md`:** the exact `introducedAt` OS version for
"Making onscreen content available to Siri and Apple Intelligence" (DocC JSON endpoint 404s for this article page)
and whether the owner has confirmed `LogTransactionIntent` responds to actual spoken Siri (not just the Shortcuts
app) on their free-Personal-Team device build.
