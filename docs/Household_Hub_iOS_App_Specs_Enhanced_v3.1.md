# Household Hub for iOS
## Product Requirements, Architecture, Data Model, UX, and Coding-Agent Specification

**Target platform:** iPhone, minimum iOS 26.0
**Primary design target:** iPhone 16 Pro Max, while retaining responsive layout behavior for future iPhone sizes
**Document version:** 3.1
**Status:** Implementation-ready technical specification; research-updated for zero-cost development and Claude Code
**Date:** September 25, 2026
**Supersedes:** Household Hub specification v1.0 / v3.0

> **v3.1 changelog (audit pass):** fixed an unterminated Markdown code fence in §10.3 that was corrupting the rendering of every section from §11 onward; fixed a camelCase inconsistency in `AppSettings.aiInsightsEnabled`; added §23–§29 to close gaps found during audit — screen/navigation UX (the document's title promises "UX" but v3.0 never specified it), a deterministic Quick Add grammar (v3.0 said the deterministic core must work with AI off but never defined what the deterministic parser actually does), a concrete backup DTO schema, performance budgets, inter-phase quality gates, and a recommendation for splitting this file for token-efficient agent sessions. See §23 for the full list with rationale.

 > This document is the master implementation specification for Household Hub. It incorporates the original product requirements, the previous architecture enhancement, and the subsequent research into modern Apple development and Claude Code workflows. It preserves the product intent while making implementation choices explicit for correctness, maintainability, accessibility, data integrity, testing, and future extensibility.
>
> **Cost constraint:** the developer has no Apple Developer Program membership and no paid third-party development services other than the existing Claude subscription. The app and development workflow must therefore be designed so that paid Apple capabilities, paid cloud services, paid APIs, paid analytics, and paid CI are never prerequisites for core development or testing.

---

# 0. Executive Technical Decisions

The following decisions are intentional and should be treated as defaults unless a later product requirement explicitly overrides them.

| Area | Decision |
|---|---|
| Cost model | Zero-cost development and use are mandatory. Paid Apple Developer Program membership and paid third-party services are not prerequisites for core functionality. The existing Claude subscription is the only paid development service assumed. |
| Persistence | SwiftData, local-first, with the main app as the authoritative store. App Group shared persistence is used only when the required entitlement is available; otherwise widgets are simulator/preview-only and cannot be a core dependency. |
| Sync | No automatic cloud synchronization in v1 |
| Architecture | Feature-oriented SwiftUI app + shared domain/persistence module; avoid heavyweight enterprise MVVM boilerplate |
| Presentation state | `@Observable` reference types for feature state; `@Query` where it genuinely simplifies read-only SwiftUI screens |
| Persistence concurrency | `ModelActor` for background/domain persistence work where appropriate; main actor for UI state |
| Money storage | Persist integer minor units (`Int64`) plus currency code; use `Decimal` only at input/calculation boundaries where appropriate |
| Recurrence | Dedicated pure recurrence engine; persist a recurrence definition rather than generating thousands of future transactions |
| Transactions | Explicit state and source metadata; never rely on scattered booleans for accounting meaning |
| Categories | Relationship to a `Category` model, not free-form strings |
| Tasks | Dedicated `TaskItem`, `SubtaskItem`, and `BoardColumn` models |
| Wishlist purchases | A purchase is a transaction linked to the wishlist item; never duplicate monetary records |
| Analytics | Deterministic calculation layer first; AI adds narrative interpretation only after deterministic results exist |
| AI | Optional on-device Foundation Models only; no external AI API is required or assumed |
| Natural language | Parse into a validated draft object first; never allow the language model to write directly to SwiftData |
| Widgets | Glanceable + interactive actions; implement the extension, but do not make App Group provisioning on a physical device a v1 prerequisite under the free Personal Team |
| Export | User-triggered CSV/backup; optional Google Sheets export using free Google APIs; no background upload |
| Backup | Versioned, portable DTO-based backup format, not a raw SwiftData database dump |
| Google auth | OAuth flow with least-privilege export scope; credentials in Keychain; no paid Google service is assumed |
| Security | iOS data protection + optional biometric gate; biometric lock is a UI gate, not a replacement for storage encryption |
| Testing | Swift Testing for new domain/service tests; XCTest/XCUIAutomation for UI and performance tests |
| CI | Local Xcode/xcodebuild verification is authoritative. GitHub Actions is optional only when its current free allowance is sufficient; paid CI is never required. |
| Telemetry | No third-party analytics or crash-reporting SDK; use local Xcode diagnostics/Instruments |
| Dependencies | Apple frameworks first; zero external packages initially. Add a package only after a documented need, license review, and maintenance check |
| Claude Code | Terminal-based Claude Code using the existing paid Claude subscription; do not configure an Anthropic API key or any separately billed API path |

---

# 1. Product Vision

Household Hub is a fast, private, local-first iPhone application that combines three closely related household functions:

1. **Budget and transaction management**
   - Income and expenses
   - Pending items
   - Recurring transactions
   - Current and projected balance
   - Categories and spending analysis

2. **Wishlist management**
   - Desired purchases
   - Estimated and actual price
   - Priority
   - Notes and optional images
   - A direct purchase flow that creates a real budget transaction

3. **Task management**
   - Kanban-style board
   - Customizable columns
   - Priorities and due dates
   - Subtasks
   - Links between tasks, wishlist items, and transactions

The application should feel like a native Apple app rather than a web application placed inside a phone frame. Data entry should be exceptionally quick, the information hierarchy should remain understandable without training, and every important action should have an obvious reversible or confirmable path.

## 1.1 Product principles

### Principle A: Capture first, organize second
The user should be able to record an item with the minimum information necessary and enrich it later.

Example:

> `47.50 coffee`

should be enough to create an expense. Category, merchant normalization, notes, and other metadata can be added afterward.

### Principle B: Deterministic core, intelligent layer on top
Money calculations, balances, recurrence, dates, validation, and data relationships must never depend on a generative model.

AI may suggest, summarize, extract, or classify, but the underlying application must remain completely correct with every AI feature disabled.

### Principle C: One source of truth
A purchase should not create a second unrelated copy of the same financial event. A wishlist item references its resulting transaction. Analytics read transactions rather than trying to reconstruct purchases from wishlist state.

### Principle D: Local first means local by default
No login, remote account, analytics SDK, or cloud database is required for normal use.

### Principle E: Failure must be graceful
A missing AI model, failed Google authorization, unavailable network, malformed backup, or widget refresh failure must never corrupt local records or make the core app unusable.

### Principle F: Build for the current platform without hard-coding temporary assumptions
The primary target is iOS 26+, but layout and service boundaries should avoid unnecessary dependencies on one exact phone dimension or one exact Apple Intelligence model version.

Apple's current Foundation Models documentation notes that the on-device model can change as the operating system is updated, so prompts and structured-output behavior should be tested against the supported OS versions rather than treated as permanently fixed. 

---

# 2. Scope

## 2.1 Version 1 scope

### Included

- Local household financial records
- Income and expense transactions
- Pending transaction state
- Recurring transaction definitions
- One default household balance context, with the data model capable of supporting multiple accounts later
- User-defined categories
- Wishlist items
- Wishlist-to-purchase conversion
- Kanban task board
- Custom columns
- Subtasks
- Links between tasks, wishlist items, and transactions
- Dashboard
- Budget/transactions screen
- Wishlist screen
- Tasks screen
- Analytics screen
- Settings
- CSV export
- Full portable backup and restore
- Optional Google Sheets export
- Optional Face ID gate
- Optional Apple Intelligence / Foundation Models assistance when supported by the device and OS
- Home Screen widgets (implemented as an optional extension; physical-device shared-data testing requires the relevant Apple entitlement/developer membership)
- Accessibility support
- Dark Mode
- Localization-ready strings

## 2.2 Explicit non-goals for the first release

Do not implement these as hidden assumptions:

- Automatic bank account synchronization
- Plaid or financial institution aggregation
- Multi-user household collaboration
- Server-side synchronization
- Subscription billing
- Advertising
- Third-party behavioral analytics
- Investment portfolio management
- Tax preparation
- Cryptocurrency accounting
- Automatic merchant transaction import from banks
- Financial advice or financial recommendations

These may be future features, but they should not complicate the v1 architecture.

---

# 3. Technical Platform

## 3.1 Required platform

- Swift 6+
- SwiftUI
- iOS 26+
- Xcode current stable release compatible with iOS 26 SDK
- SwiftData
- Swift Charts
- WidgetKit
- App Intents
- Foundation
- Observation
- LocalAuthentication
- PhotosUI
- CryptoKit where appropriate
- Foundation Models where available
- App Intents where supported, without making Siri/system integration a core release gate
- Google Sheets REST API only in the optional export integration
- Swift Testing for new non-UI tests
- XCTest/XCUIAutomation for UI and performance testing

## 3.2 Dependency philosophy

Prefer Apple frameworks and first-party APIs.

Third-party libraries should require explicit justification based on one of:

1. A substantial reduction in implementation complexity.
2. A security advantage.
3. A capability that Apple does not provide.
4. A major improvement in reliability that can be maintained long term.

Do not add a networking abstraction, dependency injection framework, database wrapper, routing framework, animation library, analytics SDK, or design-system package merely because such packages exist.

### 3.2.1 Zero-dependency baseline

Start v1 with **zero third-party Swift packages** unless implementation evidence shows that a package is necessary. Prefer:

- `URLSession` over Alamofire.
- Foundation `Codable` over JSON helper packages.
- Native CSV generation over a CSV package unless requirements become materially more complex.
- Swift Testing/XCTest over third-party test frameworks.
- SwiftUI/Observation over a dependency-injection framework.
- Keychain Services over a Keychain wrapper.
- Foundation Models, Vision, PhotosUI, App Intents, WidgetKit, and other Apple frameworks over third-party equivalents.

A third-party package is permitted only after Claude Code records the reason, license, repository health, transitive dependency impact, minimum OS/toolchain requirements, and an exit strategy.

### 3.2.2 Research candidate packages, not default packages

The research identified mature open-source options such as Alamofire, AppAuth, CodableCSV, GRDB, Kingfisher, SwiftFormat/SwiftLint, and similar libraries. These are **candidate tools**, not requirements. The default implementation should remain native. A package may be adopted later if it removes substantial complexity without introducing a new service, recurring cost, unacceptable privacy exposure, or long-term maintenance burden.

## 3.3 Suggested Xcode target structure

```text
HouseholdHub/
├── HouseholdHubApp/                 # Main iOS application target
├── HouseholdHubWidget/              # Widget extension
├── HouseholdHubCore/                # Shared local Swift package / framework
│   ├── Domain/
│   ├── Persistence/
│   ├── Services/
│   ├── Analytics/
│   ├── ImportExport/
│   └── Utilities/
├── HouseholdHubTests/               # Unit + integration tests
├── HouseholdHubUITests/             # Critical UI flows
└── SharedResources/                 # Shared assets/localized resources
```

The shared module must not import SwiftUI unless there is a compelling reason. Keep domain and persistence code usable by both the app and widget target.

## 3.4 Recommended source organization

Use feature folders in the application target:

```text
Features/
├── Dashboard/
├── Budget/
├── Wishlist/
├── Tasks/
├── Analytics/
├── Settings/
├── QuickAdd/
└── Shared/
```

Within each feature:

```text
FeatureName/
├── FeatureView.swift
├── FeatureViewModel.swift       # only where state is non-trivial
├── Components/
├── Sheets/
└── FeatureRoutes.swift          # only where routing is needed
```

Do not create one view model per SwiftUI view automatically. Simple views should remain simple SwiftUI views.

---

# 4. Application Architecture

## 4.1 Architectural style

Use a lightweight feature-oriented architecture with explicit domain services.

```text
SwiftUI Views
     │
     ▼
Feature State / @Observable
     │
     ▼
Use Cases / Domain Services
     │
     ├───────────────┐
     ▼               ▼
Persistence      External Services
SwiftData        Google / AI / Files
```

The key boundary is not "View → ViewModel → Repository → Everything." The key boundary is:

- UI state
- deterministic business rules
- persistence
- optional external integrations

## 4.2 Main actor rules

UI presentation state should be `@MainActor`.

Do not perform large database fetches, analytics over thousands of records, image processing, export preparation, or AI generation synchronously on the main actor.

Use structured concurrency:

- `async/await`
- actors for isolated services
- `ModelActor` for isolated SwiftData work where appropriate
- task cancellation when a view disappears or the user changes filters

Apple explicitly provides `ModelActor` and serial model executors for safe isolated SwiftData storage work.

## 4.3 Observable state

Use `@Observable` for complex feature state.

Example conceptual state:

```swift
@MainActor
@Observable
final class BudgetViewModel {
    var selectedPeriod: BudgetPeriod = .currentMonth
    var selectedCategoryID: UUID?
    var selectedTransactionType: TransactionTypeFilter = .all
    var showPendingOnly = false
    var isPresentingQuickAdd = false
}
```

Do not mirror every model property into a view model. SwiftData models remain the source of persisted truth.

## 4.4 Service boundaries

Implement small services with explicit responsibilities:

```text
QuickAddCoordinator
TransactionService
WishlistService
TaskService
RecurrenceEngine
BalanceCalculator
AnalyticsEngine
NaturalLanguageParser
CategorySuggestionService
InsightGenerator
BackupService
CSVExportService
GoogleSheetsExportService
ImageStore
BiometricGate
WidgetSyncService
```

A service should have one clear reason to change.

---

# 5. Persistence Architecture

## 5.1 SwiftData

Use SwiftData as the primary persistence framework.

The app must have one authoritative persistent model container for the main data store.

The core app must work correctly without any Apple Developer Program membership. Do not make a widget entitlement, App Group, iCloud container, or other paid-capability provisioning step a dependency of the main app.

## 5.2 Widget/App Group boundary

Apple documents App Groups as the mechanism for sharing a container between an app and its widget extension. However, App Groups are an entitlement that requires the appropriate developer provisioning. The free Personal Team can install and test a normal app on a personal device, but advanced capabilities such as App Groups are not part of the no-membership baseline.

Therefore implement the widget boundary as follows:

```text
Core app data
    ↓
WidgetDataProvider protocol
    ├── FreeDevelopmentWidgetDataProvider
    │     └── Simulator / Preview fixture data only
    └── AppGroupWidgetDataProvider
          └── Enabled only when App Group entitlement is available
```

The production-capable App Group path should still be designed and coded, but physical-device widget validation must not block v1 development under a free account. When/if the user later joins the Apple Developer Program, the App Group identifier can be enabled without redesigning the app.

When enabled, use a stable identifier such as:

```text
group.com.<developer>.HouseholdHub
```

Do not hard-code an identifier that cannot be changed per developer/team configuration.

The shared module should expose one persistence factory so that the app and widget do not independently construct subtly different stores.

Conceptual interface:

```swift
struct PersistenceConfiguration {
    let useInMemoryStore: Bool
    let appGroupIdentifier: String?
}

protocol PersistenceContainerFactory {
    func makeContainer(configuration: PersistenceConfiguration) throws -> ModelContainer
}
```

Do not expose raw `ModelContext` instances across actor boundaries.

## 5.3 Persistent store configuration

Requirements:

- Persistent on disk.
- No CloudKit configuration in v1.
- App Group-backed when widgets are enabled.
- In-memory configuration available for previews and unit tests.
- Explicit schema and migration plan.
- No destructive migration in production.

SwiftData supports explicit `SchemaMigrationPlan` and versioned schemas; define the migration architecture before adding additional releases.

## 5.4 Query strategy

Avoid a single enormous `@Query` in the dashboard containing all historical transactions.

Instead:

- Fetch only the relevant date range.
- Apply predicates at the persistence layer.
- Sort in the store when practical.
- Keep UI result sets bounded.
- Use explicit fetch descriptors for service-layer analytics.
- Avoid repeatedly loading image blobs with list records.

For long transaction histories, use pagination or incremental loading.

## 5.5 Image storage

Do not store large receipt or wishlist image binaries directly in every SwiftData row.

Use:

```text
Application Support/
└── Media/
    ├── Wishlist/
    └── Receipts/
```

Store a stable relative media identifier/path in SwiftData.

Benefits:

- Smaller database rows
- Faster list queries
- Better backup control
- Easier future migration
- Ability to generate thumbnails without loading full-size images

The `ImageStore` must provide:

```swift
save(image:) async throws -> MediaReference
loadThumbnail(for:) async throws -> Data?
delete(_:) async throws
```

Store thumbnails separately where beneficial.

---

# 6. Money and Currency Model

The original specification uses `Decimal` for persisted monetary values. For a production budget application, use integer minor units as the canonical stored representation.

## 6.1 Canonical representation

Recommended model:

```swift
struct Money: Codable, Hashable, Sendable {
    let minorUnits: Int64
    let currencyCode: String
}
```

Examples for CAD:

```text
$47.50 → 4750
$1,000.00 → 100000
-$12.99 → -1299
```

This prevents floating-point ambiguity and makes equality, aggregation, sorting, and persistence deterministic.

`Decimal` should be used at input/parsing boundaries when required, then converted into validated minor units.

## 6.2 Currency policy

Version 1 supports one active household currency.

Store:

```text
currencyCode = "CAD"
```

Do not store currency symbols in the database.

Use Foundation currency formatting at presentation time.

The UI should obtain the symbol and locale-sensitive formatting from the selected currency and current locale.

## 6.3 Currency changes

Changing currency after transactions exist must never silently reinterpret historic values.

Preferred behavior:

1. If no financial records exist, change freely.
2. If records exist, warn the user.
3. Require explicit confirmation.
4. Preserve existing transaction currency if multi-currency support is eventually introduced.
5. For v1, recommend that users establish a new data set instead of silently converting historical values.

## 6.4 Monetary calculations

Centralize all money arithmetic in one module.

Never perform accounting calculations using `Double`.

Required functions:

```text
add
subtract
sum
negate
compare
percentage
average
roundForDisplay
format
```

All arithmetic operations should be covered by unit tests, including large amounts and negative values.

---

# 7. Data Model

The data model should favor relationships and explicit state instead of duplicated strings and booleans.

## 7.1 Common model conventions

Every persistent model should have:

```text
id: UUID
createdAt: Date
updatedAt: Date
```

Where appropriate:

```text
archivedAt: Date?
```

Use UUIDs as stable internal identifiers.

Do not use array indexes as identifiers.

## 7.2 Transaction

Recommended conceptual model:

```text
Transaction
├── id: UUID
├── amountMinorUnits: Int64
├── currencyCode: String
├── type: TransactionType
├── status: TransactionStatus
├── occurredAt: Date
├── merchantID: UUID?
├── categoryID: UUID?
├── notes: String?
├── recurringSeriesID: UUID?
├── source: TransactionSource
├── wishlistItemID: UUID?
├── isAIClassified: Bool
├── createdAt: Date
├── updatedAt: Date
```

### TransactionType

```text
income
expense
transfer       # reserved for multi-account support
```

Transfers should remain disabled in the UI until account support is released, but the enum can be reserved now if the architecture permits it cleanly.

### TransactionStatus

```text
posted
pending
cancelled
```

Avoid an `isPending` boolean. Explicit state scales better as behavior grows.

### TransactionSource

```text
manual
wishlistPurchase
recurring
imported
widget
naturalLanguage
```

Source is provenance, not accounting classification.

## 7.3 Category

```text
Category
├── id: UUID
├── name: String
├── icon: String
├── color: String / Codable ColorToken
├── kind: CategoryKind
├── sortOrder: Int
├── isSystem: Bool
├── isArchived: Bool
├── createdAt: Date
└── updatedAt: Date
```

### CategoryKind

```text
income
expense
both
```

The UI should prevent an expense-only category from being accidentally selected for income unless the user has explicitly configured it for both.

### Color storage

Do not store arbitrary serialized SwiftUI `Color` values.

Store a semantic color token or normalized RGB/HSB components in a Codable value object.

Suggested approach:

```text
ColorToken
├── red: UInt8
├── green: UInt8
├── blue: UInt8
├── alpha: UInt8
```

Provide validation and accessibility contrast checks in the design system.

## 7.4 Merchant

Add an optional normalized merchant model:

```text
Merchant
├── id: UUID
├── displayName: String
├── normalizedName: String
├── defaultCategoryID: UUID?
├── createdAt: Date
└── updatedAt: Date
```

This enables consistent category suggestions without relying solely on raw free-form strings.

A transaction can store a `merchantID?` while retaining a snapshot of the original entered merchant name if needed for future data integrity.

## 7.5 RecurringTransaction

Do not model recurrence as a Boolean + optional rule directly on the transaction if recurrence is expected to evolve.

Use a dedicated series:

```text
RecurringTransaction
├── id: UUID
├── templateAmountMinorUnits: Int64
├── currencyCode: String
├── type: TransactionType
├── categoryID: UUID?
├── merchantID: UUID?
├── notes: String?
├── rule: RecurrenceRule
├── startDate: Date
├── endDate: Date?
├── nextOccurrence: Date
├── isEnabled: Bool
├── createdAt: Date
└── updatedAt: Date
```

Generated transactions reference the recurring series.

## 7.6 RecurrenceRule

Persist a strongly typed Codable value rather than a human-readable text string.

Supported v1 forms:

```text
weekly(interval, weekday)
monthly(dayOfMonth)
monthly(nthWeekday)
yearly(month, day)
```

Optional later forms:

```text
daily(interval)
weekdayOnly
custom RRULE-compatible
```

The UI should hide unsupported complexity until needed.

## 7.7 WishlistItem

```text
WishlistItem
├── id: UUID
├── name: String
├── estimatedPriceMinorUnits: Int64
├── actualPriceMinorUnits: Int64?
├── currencyCode: String
├── priority: Priority
├── status: WishlistStatus
├── categoryID: UUID?
├── notes: String?
├── mediaReference: String?
├── linkedTaskID: UUID?
├── purchasedTransactionID: UUID?
├── targetDate: Date?
├── createdAt: Date
└── updatedAt: Date
```

### WishlistStatus

```text
wanted
pending
purchased
archived
```

`purchasedTransactionID` is the authoritative connection to the actual spending event.

## 7.8 TaskItem

Avoid naming the model simply `Task` because Swift concurrency already uses `Task` heavily.

Use:

```text
TaskItem
├── id: UUID
├── title: String
├── notes: String?
├── columnID: UUID
├── priority: Priority
├── dueDate: Date?
├── completedAt: Date?
├── sortOrder: Double
├── linkedWishlistItemID: UUID?
├── linkedTransactionID: UUID?
├── archivedAt: Date?
├── createdAt: Date
└── updatedAt: Date
```

## 7.9 SubtaskItem

Do not store subtasks as `[String]`.

Use a relationship:

```text
SubtaskItem
├── id: UUID
├── title: String
├── isCompleted: Bool
├── sortOrder: Double
├── taskID: UUID
├── createdAt: Date
└── updatedAt: Date
```

This allows future due dates, notes, and individual completion timestamps without a destructive redesign.

## 7.10 BoardColumn

```text
BoardColumn
├── id: UUID
├── name: String
├── sortOrder: Int
├── isSystem: Bool
├── createdAt: Date
└── updatedAt: Date
```

Use a sort-order integer with a small rebalance operation after manual reordering. Board columns will be small in number, so a simple deterministic approach is preferable to an elaborate ranking algorithm.

## 7.11 AppSettings

Use a single persistent settings entity for durable application configuration that must be included in backups.

```text
AppSettings
├── id: UUID              # singleton
├── currencyCode: String
├── onboardingCompleted: Bool
├── startingBalanceMinorUnits: Int64
├── startingBalanceDate: Date
├── defaultAnalyticsPeriod: AnalyticsPeriod
├── selectedTheme: ThemePreference
├── accentColor: ColorToken
├── faceIDEnabled: Bool
├── aiCategorizationEnabled: Bool
├── naturalLanguageEnabled: Bool
├── aiInsightsEnabled: Bool
├── widgetShowsBalance: Bool
├── defaultQuickAddType: QuickAddType
├── createdAt: Date
└── updatedAt: Date
```

Do not use `@AppStorage` for settings that must be backed up or migrated. Use `@AppStorage` only for transient UI preferences where persistence in the backup is unnecessary.

## 7.12 Export configuration

Google authentication state should not be stored as raw access tokens in SwiftData.

Use a separate export configuration model for non-secret metadata:

```text
GoogleExportConfiguration
├── id: UUID
├── lastSpreadsheetID: String?
├── lastSheetName: String?
├── lastExportDate: Date?
└── createdAt / updatedAt
```

Credentials/tokens belong in the Keychain, not SwiftData. Apple identifies Keychain Services as the appropriate storage for small secrets such as credentials and cryptographic keys.

---

# 8. Relationships and Deletion Rules

## 8.1 Wishlist purchase relationship

When a wishlist item is purchased:

1. User confirms actual price.
2. Create exactly one expense transaction.
3. Set the transaction source to `wishlistPurchase`.
4. Link the transaction to the wishlist item.
5. Set the wishlist status to `purchased`.
6. Save all changes atomically within one model transaction/context operation.

If any step fails, do not leave a half-completed purchase state.

## 8.2 Deleting a wishlist item

Deleting a wishlist item must not delete its transaction automatically.

If a wishlist item has a linked transaction:

- Ask whether to archive the wishlist item or delete it.
- Never silently delete accounting history.

## 8.3 Deleting a transaction

Transactions are financial history.

Use a confirmation dialog that explicitly tells the user what will happen.

If a transaction belongs to a recurring series, deleting the transaction instance must not automatically disable the series. Offer:

```text
Delete this occurrence
Delete this occurrence and disable the series
Cancel
```

## 8.4 Deleting a category

If a category is referenced by transactions:

- Do not hard-delete it.
- Offer to archive it.
- Optionally reassign affected transactions to another category.

System categories should never be hard-deleted.

## 8.5 Deleting a board column

If tasks exist in a column:

- Require a destination column.
- Move tasks before deleting the source column.

Never orphan tasks.

---

# 9. Accounting Rules

## 9.1 Starting balance

The starting balance is a baseline, not a transaction.

Store:

```text
startingBalanceMinorUnits
startingBalanceDate
```

Current balance:

```text
starting balance
+ posted income after starting date
- posted expenses after starting date
```

Pending transactions are excluded from the default posted balance.

## 9.2 Pending balance

Show three distinct concepts when useful:

```text
Current balance       = posted only
Pending impact        = pending income/expense impact
Projected balance     = current + scheduled/known future items
```

Do not use the word "balance" for all three.

## 9.3 Projected balance

The default dashboard projection is 30 calendar days.

Projection inputs:

- Posted transactions through today
- Pending transactions where the user has chosen to include them
- Recurring occurrences inside the projection window
- Optional future dated manual transactions

Projection must be deterministic.

## 9.4 Recurring occurrence policy

Do not generate infinite future transaction objects.

At minimum, calculate the next occurrence dynamically.

For analytics and projection:

```text
recurrence series
→ occurrence generator
→ bounded date range
→ projected transactions
```

Generate real transaction records only when the user explicitly posts or materializes an occurrence.

This prevents duplicate data and makes changing a recurring rule much safer.

---

# 10. Date and Time Policy

Date handling is a major source of subtle bugs and must be centralized.

## 10.1 Absolute events

Transactions represent an event in time and use `Date` internally.

## 10.2 Calendar-based concepts

Recurrence rules operate in a stored calendar/time-zone context.

Store the time zone identifier associated with the recurrence definition where relevant.

For example:

```text
America/Vancouver
```

Do not assume UTC for calendar calculations.

## 10.3 Day boundaries

Centralize all date calculations in `HouseholdCalendar`.

Required operations:

```text
startOfDay
endOfDay
startOfWeek
startOfMonth
endOfMonth
startOfYear
relativeDayLabel
```

---

# 11. Zero-Cost Development and Capability Matrix

This section is a hard constraint for the implementation agent. Do not introduce a dependency on a paid account or paid service merely because it is convenient.

## 11.1 Allowed baseline

The project must be fully buildable and testable with:

- macOS
- Xcode from the Mac App Store
- iOS Simulator
- a standard Apple Account / free Personal Team for optional physical-device testing
- Git
- Swift Package Manager
- local Xcode command-line tools
- the user's existing Claude subscription with Claude Code
- free/open-source packages only when a package is explicitly approved

Apple states that Xcode and personal-device testing do not require Apple Developer Program membership. A free Personal Team can provision up to 10 App IDs and 3 devices, with provisioning expiring after 7 days, so apps need periodic reinstallation/reprovisioning under this setup.

## 11.2 Capability matrix

| Capability | No-cost development status | Rule for Household Hub |
|---|---|---|
| SwiftUI / SwiftData / Swift Charts | Fully available | Core |
| iOS Simulator | Fully available | Primary development/test environment |
| Physical iPhone app testing | Available with free Personal Team, subject to short-lived provisioning | Optional; never the only test path |
| Local notifications | No paid developer membership required for basic local scheduling | Allowed |
| Foundation Models on-device | No separate paid API required for the on-device model; availability depends on supported OS/device/system intelligence state | Optional AI layer; core app works without it |
| PhotosUI / Vision / OCR | Apple framework | Allowed |
| App Intents | Framework is usable in code; some system-level integrations/capabilities may require additional provisioning | Implement where useful, but never a release blocker |
| WidgetKit extension | Code can be developed/tested in simulator and previews | Optional extension; do not assume free physical-device App Group provisioning |
| App Groups/shared widget store | Requires the relevant entitlement/provisioning | Deferred physical-device capability until paid membership is available |
| CloudKit/iCloud sync | Membership/capability dependent | Out of scope |
| TestFlight | Requires Apple Developer Program membership | Out of scope |
| App Store distribution | Requires Apple Developer Program membership | Out of scope |
| Sign in with Apple for app authentication | Requires Apple Developer capabilities/configuration | Out of scope; the app requires no user account |
| Push notifications | Entitlement/distribution dependent | Out of scope; use local notifications only if needed |
| Google Sheets export | Can use free Google account/API quotas, but requires Google-side OAuth configuration | Optional; no paid quota or backend may be assumed |
| GitHub repository | Free account/repo options are sufficient for source control | Recommended but not mandatory |
| GitHub Actions | May have free allowance, but hosted macOS CI consumes quota | Optional convenience only; local CI remains authoritative |
| Firebase / Sentry / Amplitude / similar | Free tiers may exist but add external telemetry/service dependencies | Do not use |
| Anthropic API key | Separate API billing path | **Do not use**; use Claude Code via the existing Claude subscription |

## 11.3 Product requirement consequence

A feature is not considered part of the core v1 product if it cannot be exercised with the free baseline above.

The agent must distinguish:

```text
CORE
    Works locally, offline, without paid entitlements.

OPTIONAL
    Works with free external services but is not required for correctness.

DEFERRED CAPABILITY
    Code may be prepared now, but real-device/prod use requires paid Apple membership or another unavailable capability.
```

Any proposed dependency that moves a CORE feature into OPTIONAL or DEFERRED status requires explicit approval.

---

# 12. Apple Intelligence and Foundation Models Strategy

## 12.1 No external AI service requirement

The app's intelligence layer must use Apple's on-device Foundation Models when available. Do not build v1 around a cloud LLM API, including Anthropic's API, OpenAI APIs, or another metered model provider.

Apple's current Foundation Models APIs provide access to the on-device Apple Foundation model, and Apple explicitly notes that model behavior can change across OS updates. Prompts and structured-output assumptions therefore require regression tests against the supported OS/toolchain rather than being treated as immutable.

## 12.2 AI architecture

```text
User input
    ↓
Deterministic pre-parser
    ↓
AI suggestion request (optional)
    ↓
Structured output
    ↓
Validation layer
    ↓
Human-reviewable draft
    ↓
Deterministic domain command
    ↓
SwiftData
```

AI never receives direct access to the persistence layer.

## 12.3 AI features in scope

Preferred v1 capabilities:

- Natural-language Quick Add parsing
- Category suggestion
- Merchant normalization suggestion
- Receipt text/image extraction where supported
- Transaction/task/wishlist drafting
- Analytics narrative summaries
- Smart search interpretation

Each feature must have a deterministic fallback.

## 12.4 Model version resilience

Maintain AI regression fixtures such as:

```text
AIFixtures/
├── quick-add/
├── categorization/
├── receipt-extraction/
└── insights/
```

Each fixture contains:

- input
- expected structured fields
- allowed alternatives
- validation rules
- model/OS metadata when relevant

When Apple's model changes, rerun the fixture suite and update prompts or validators if necessary. Apple explicitly documents that the underlying on-device model changes across OS updates.

## 12.5 No cloud fallback in core behavior

Do not implement:

```text
Apple on-device model failed → silently send financial data to a cloud LLM
```

Instead:

```text
Apple model unavailable
→ deterministic parser / manual input
→ user can continue normally
```

This preserves the product's local-first privacy promise and zero-paid-service constraint.

---

# 13. Testing Architecture

## 13.1 Swift Testing for new unit/domain tests

Use **Swift Testing** for new unit, domain, parsing, recurrence, accounting, and service tests. Apple recommends Swift Testing for new unit-test development while retaining XCTest for UI and performance testing.

Use parameterized tests aggressively for:

- Money arithmetic
- Currency formatting cases
- Recurrence rules
- End-of-month behavior
- Leap years
- DST/time-zone transitions
- Category matching
- Quick Add parsing
- Backup import validation

Example style:

```swift
import Testing

@Test(arguments: [
    ("2026-01-31", "monthly day 31", "2026-02-28"),
    ("2024-01-31", "monthly day 31", "2024-02-29")
])
func monthlyRecurrenceCases(...) {
    #expect(...)
}
```

## 13.2 XCTest remains for UI

Use XCTest/XCUIAutomation for:

- Launch and onboarding
- Quick Add flow
- Transaction creation
- Wishlist purchase conversion
- Task creation and movement
- Import/restore confirmation
- Accessibility-driven UI checks
- Performance tests where appropriate

Do not mix Swift Testing and XCTest APIs within the same individual test implementation. Apple supports both in the same test target and provides interoperability for gradual adoption.

## 13.3 Test layers

```text
Layer 1: Pure domain tests
Layer 2: Persistence integration tests
Layer 3: Import/export tests
Layer 4: AI structured-output validation tests
Layer 5: UI automation tests
Layer 6: Manual simulator/device smoke tests
```

No merge is complete until the relevant lower layers pass.

---

# 14. Local CI and Verification Strategy

Because paid CI is not available, local verification is the authoritative quality gate.

## 14.1 Required local commands

The repository should provide scripts with stable entry points:

```text
Scripts/
├── bootstrap.sh
├── format.sh
├── lint.sh
├── test.sh
├── ui-test.sh
├── verify.sh
└── doctor.sh
```

The scripts must work from the repository root and should fail fast with clear error messages.

`verify.sh` should perform, at minimum:

```text
1. Check Xcode/toolchain availability
2. Check project generation/configuration
3. Format/lint validation
4. Build for iOS Simulator
5. Run unit/integration tests
6. Run critical UI tests when practical
7. Report failures with the smallest useful diagnostic output
```

## 14.2 GitHub Actions

A GitHub Actions workflow may be included for convenience, but it must not be the only way to verify the app and must never require paid runner minutes.

The workflow should:

- use the repository's local scripts
- use the Xcode version actually documented by the project
- build against an available simulator destination
- preserve `.xcresult` artifacts when possible
- avoid third-party SaaS coverage uploaders

If free macOS CI quota is unavailable, the workflow should fail with a clear explanation rather than silently assuming paid minutes.

---

# 15. Claude Code Environment and Execution Protocol

This project is designed around Claude Code as the primary coding agent. The goal is not to make Claude autonomous at all costs; it is to give it a disciplined operating environment where it can plan, edit, build, test, inspect, and self-correct while preserving the developer's control.

Claude Code currently supports terminal/IDE surfaces, project instructions via `CLAUDE.md`, skills, hooks, MCP connections, subagents, and verification workflows.

## 15.1 Installation

Use the current official Claude Code installer rather than pinning an old installer command into the repository.

For macOS, the current official options include:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

or:

```bash
brew install --cask claude-code
```

Start in the repository:

```bash
cd HouseholdHub
claude
```

Claude Code prompts for sign-in on first use. **Do not set `ANTHROPIC_API_KEY` for this project** because the user's paid Claude subscription is the intended billing/authentication path; an API key is a separate API service/billing path. The official Claude Code documentation confirms subscription-based use on supported surfaces and API-key authentication as a distinct option.

## 15.2 Repository control files

The repository must contain:

```text
HouseholdHub/
├── CLAUDE.md
├── .claude/
│   ├── settings.json
│   ├── settings.local.json        # git-ignored
│   ├── skills/
│   └── agents/                    # only when custom subagents are useful
├── .mcp.json                      # only project-scoped MCPs that are intentionally shareable
├── Scripts/
├── docs/
└── HouseholdHub.xcodeproj / .xcworkspace
```

## 15.3 CLAUDE.md requirements

`CLAUDE.md` is the primary project contract and must contain:

```text
1. Product purpose
2. Zero-cost constraint
3. Architecture decisions
4. Persistence rules
5. Money/accounting rules
6. AI safety rules
7. Dependency policy
8. Testing commands
9. Formatting/linting commands
10. Git rules
11. Definition of Done
12. Research/source verification rules
```

Claude Code reads `CLAUDE.md` at the start of sessions. Use it for durable facts and architecture decisions, not long procedural checklists that belong in skills. Claude Code's skill system is designed so longer procedural material loads only when the skill is invoked.

## 15.4 Required Claude Code skills

Create these project-local skills:

```text
.claude/skills/
├── household-verify/
│   └── SKILL.md
├── household-build/
│   └── SKILL.md
├── household-test/
│   └── SKILL.md
├── household-ui-review/
│   └── SKILL.md
├── household-accessibility-audit/
│   └── SKILL.md
├── household-migration-audit/
│   └── SKILL.md
├── household-data-safety-review/
│   └── SKILL.md
├── household-dependency-audit/
│   └── SKILL.md
└── household-research-apple-api/
    └── SKILL.md
```

### `household-verify`

Purpose: the main end-of-feature verification loop.

Required behavior:

```text
Read current diff
→ inspect affected architecture boundaries
→ run formatting/linting
→ build simulator target
→ run relevant tests
→ run UI verification when appropriate
→ inspect failures
→ fix only issues supported by evidence
→ rerun verification
→ summarize remaining risks
```

### `household-research-apple-api`

Purpose: prevent Claude from coding against stale Apple API assumptions.

Required behavior:

```text
Identify API/question
→ consult official Apple Developer documentation first
→ record minimum OS/toolchain requirements
→ record entitlement requirements
→ check deprecations/availability
→ implement only against verified API shapes
→ update project docs when the API decision affects architecture
```

Never treat a random GitHub snippet, blog post, or old Stack Overflow answer as authoritative when Apple's documentation is available.

## 15.5 Bundled Claude Code skills to use

Use the current bundled capabilities where relevant, especially:

- `/doctor` for environment/setup diagnosis
- `/run` to launch and inspect the app
- `/verify` to build/run and verify behavior
- `/debug` for reproducing and fixing failures
- `/code-review` for review passes
- `/batch` for independent repeated changes when appropriate
- `/loop` for short polling/recheck workflows

Claude Code currently documents `/run` and `/verify` as bundled skills for launching and validating applications. If needed, use `/run-skill-generator` to teach those workflows how to build and launch the Household Hub scheme.

## 15.6 Custom subagents

Do not create a swarm of agents by default. Use focused subagents only when the task can be cleanly partitioned.

Recommended roles:

```text
swift-architect
    Reviews architecture, concurrency, persistence boundaries.

ui-specialist
    Reviews SwiftUI composition, interaction, animation, accessibility.

qa-engineer
    Designs tests, reproductions, regression coverage, and verification.

data-safety
    Reviews migrations, backup/restore, accounting integrity, and destructive operations.
```

A lead Claude Code session should remain responsible for integration and final verification.

## 15.7 Hooks

Use hooks for deterministic safeguards, not for large chunks of model reasoning.

Recommended hook categories:

```text
PostToolUse
    Validate formatting on changed Swift files.

PreToolUse
    Block or require confirmation for destructive commands.

ConfigChange
    Audit modifications to .claude settings, skills, and MCP configuration.
```

Claude Code supports `PreToolUse`, `PostToolUse`, and configuration-change hooks; project settings live in `.claude/settings.json` and local overrides live in `.claude/settings.local.json`.

Do not build a hook that automatically rewrites large amounts of source code after every edit. Prefer fast validation plus explicit `/format` or `Scripts/format.sh` actions when formatting changes are needed.

## 15.8 Permissions

Start Claude Code with conservative permissions.

Claude may automatically:

- read project source
- edit project source
- run non-destructive build/test commands
- inspect Git status/diff

Claude must ask before:

- deleting project files
- deleting or rewriting persisted user data
- destructive Git operations
- changing signing identities or certificates
- changing external OAuth configuration
- adding a network service dependency
- installing a new third-party package
- modifying MCP credentials
- changing repository history

Never store secrets in:

- `CLAUDE.md`
- committed settings
- source code
- `.mcp.json`
- test fixtures

Use Keychain/environment variables/local ignored settings as appropriate.

## 15.9 MCP strategy

MCP is optional. A useful MCP is one that gives Claude reliable context or actions that it cannot obtain locally. Do not install MCP servers merely because they are available.

### Recommended initial configuration

**No MCP is required for the first local development milestone.** Claude Code already has filesystem, shell, Git, and code-editing capabilities.

### First useful MCP: GitHub

When the repository is hosted on GitHub, a GitHub MCP server can be useful for:

- issues
- pull requests
- review context
- repository metadata
- release/project tracking

Prefer a local-scoped connection when credentials are personal. Project-scoped `.mcp.json` should contain only intentionally shareable configuration, never personal secrets. Claude Code documents local scope as the default for personal/credential-bearing servers and provides `claude mcp add`, `claude mcp list`, `claude mcp get`, and `/mcp` for management.

### MCPs explicitly not recommended for v1

Do not add Slack, Jira, Notion, Google Drive, cloud databases, telemetry systems, or generic web-scraping MCPs unless a concrete project workflow later demonstrates a need. They add credentials, attack surface, context noise, and maintenance without improving the core app-building loop.

## 15.10 MCP installation procedure

For any approved MCP:

```bash
claude mcp add <name> -- <local-server-command>
claude mcp list
claude mcp get <name>
```

For remote HTTP MCP servers, use the documented `--transport http` form. Prefer local scope for personal credentials; use project scope only when the configuration is intentionally shareable. Claude Code documents both local and project MCP scopes and the server approval flow.

## 15.11 Claude Code session protocol

For every non-trivial feature, Claude should follow:

```text
1. Read CLAUDE.md and relevant skill instructions.
2. Inspect the existing implementation before proposing changes.
3. Identify affected models/services/views/tests.
4. Write a short implementation plan.
5. Implement the smallest coherent change.
6. Run focused tests.
7. Build the app.
8. Run UI verification when the change is user-facing.
9. Inspect the diff.
10. Run household-verify.
11. Summarize what changed, what was verified, and what remains uncertain.
```

Avoid asking Claude to simultaneously redesign the whole application and implement multiple unrelated features. Smaller verified slices are easier to review and produce better recovery behavior.

## 15.12 Git workflow

Recommended branch model:

```text
main
  └── feature/<short-name>
```

One logical feature per branch.

Claude must:

- inspect `git status` before editing
- avoid overwriting unrelated user work
- commit coherent changes
- avoid giant generated commits
- never force-push or rewrite history without explicit approval

Commit messages should describe the actual change, not the prompt that caused it.

---

# 16. Claude Code Project Bootstrap

The project should include a repeatable, no-cost bootstrap procedure.

## 16.1 Bootstrap sequence

Run from the repository root:

```bash
./Scripts/bootstrap.sh
claude
```

The bootstrap script should check for, rather than blindly install, the following:

```text
xcodebuild
swift
swift-format (or the documented formatter)
git
claude
```

It may offer install instructions for missing tools, but it must not silently install third-party software without user approval.

## 16.2 Initial Claude instructions

The first Claude Code session should be asked to:

```text
1. Read the full Household Hub specification.
2. Run /doctor.
3. Inspect Xcode, Swift, simulator destinations, and repository state.
4. Do not modify application code yet.
5. Produce an environment report.
6. Identify any capability that requires a paid Apple Developer Program membership.
7. Confirm that the core development path remains fully usable without paid services.
8. Only then begin implementation planning.
```

This prevents the agent from accidentally assuming access to entitlements or services that are unavailable.

## 16.3 Project reconnaissance skill

Create a first-run skill, `household-environment-audit`, that records:

```text
macOS version
Xcode version
Swift version
Swift compiler language mode
available iOS simulator runtimes
available iPhone simulator devices
physical-device connection status (if any)
Apple Account / Personal Team availability
Claude Code version
Git version
installed formatters/linters
configured MCP servers
repository remotes
```

The report must clearly distinguish:

```text
AVAILABLE
AVAILABLE WITH LIMITATION
REQUIRES PAID MEMBERSHIP
NOT INSTALLED
UNKNOWN
```

---

# 17. Recommended Free/Native Tooling Matrix

| Need | Primary choice | Secondary choice | Do not add by default |
|---|---|---|---|
| UI | SwiftUI | UIKit only when necessary | UI frameworks |
| State | Observation / `@Observable` | lightweight feature state structs | heavy DI/state libraries |
| Persistence | SwiftData | Core Data only if SwiftData blocks a requirement | Realm/SQLite wrapper |
| Money | `Int64` minor units + `Decimal` boundaries | none | `Double` |
| Networking | `URLSession` | Alamofire only with evidence | Moya/networking stacks |
| JSON | `Codable` | custom decoder where required | SwiftyJSON |
| CSV | small native exporter | CodableCSV if requirements become complex | spreadsheet SDKs |
| Auth | `ASWebAuthenticationSession` + OAuth/PKCE where appropriate | official Google Sign-In package after compatibility review | generic auth frameworks |
| Secrets | Keychain Services | wrapper only if it materially reduces risk | storing tokens in SwiftData |
| AI | Foundation Models on-device | deterministic heuristics | cloud LLM APIs |
| Image text | Vision / PhotosUI | native OCR/image processing | cloud OCR APIs |
| Charts | Swift Charts | none | third-party chart frameworks |
| Accessibility | SwiftUI Accessibility APIs + Inspector | XCTest accessibility checks | third-party accessibility layers |
| Unit tests | Swift Testing | XCTest | third-party test frameworks |
| UI tests | XCTest/XCUIAutomation | manual simulator smoke tests | paid device farms |
| Profiling | Xcode Instruments | signposts/logging | paid APM tools |
| Formatting | `swift-format` / project-standard formatter | SwiftFormat if consciously adopted | formatter plugins that mutate unpredictably |
| Lint | compiler warnings + focused checks | SwiftLint if justified | cloud-only lint services |
| CI | local `Scripts/verify.sh` | GitHub Actions within free quota | paid CI |
| Source control | Git + GitHub | local Git only | paid project management services |
| Claude integration | Claude Code + CLAUDE.md + Skills + Hooks | GitHub MCP | large third-party plugin/MCP stack |

---

# 18. Claude Code Definition of Done

Claude Code must not report a feature as complete merely because the source compiles.

A feature is complete only when all applicable criteria below are satisfied:

```text
[ ] Product requirement implemented
[ ] Existing architecture respected
[ ] No unnecessary dependency introduced
[ ] No paid service introduced
[ ] No new entitlement dependency introduced without documentation
[ ] Core logic covered by tests
[ ] Persistence behavior tested where applicable
[ ] Error states handled
[ ] Loading/empty states handled
[ ] Accessibility considered
[ ] Dynamic Type checked
[ ] Reduce Motion behavior checked
[ ] Dark Mode checked
[ ] Localization-ready strings used
[ ] Simulator build succeeds
[ ] Relevant UI flow verified
[ ] Migration implications reviewed
[ ] Backup/restore implications reviewed where applicable
[ ] Git diff reviewed
[ ] No unrelated files changed
[ ] Remaining uncertainty explicitly documented
```

For data-sensitive changes, additionally require:

```text
[ ] Accounting invariants still hold
[ ] No duplicate financial event can be created
[ ] Destructive actions are confirmed
[ ] Backup compatibility is preserved or migration is provided
```

---

# 19. Research and Documentation Maintenance

This document is a living technical contract. Apple APIs, iOS behavior, Swift toolchains, Claude Code capabilities, and package ecosystems change.

## 19.1 Source hierarchy

When an implementation question arises, Claude should prefer sources in this order:

```text
1. Official Apple Developer documentation
2. Official Anthropic / Claude Code documentation
3. Official project/package repository and release notes
4. Maintainer documentation
5. High-quality technical articles
6. Community discussions / snippets
```

The lower levels are for interpretation and examples, not for overriding documented platform behavior.

## 19.2 Version-sensitive decisions

For any API that affects architecture, Claude should record:

```text
API/framework
minimum OS
Xcode/Swift version tested
entitlement requirements
availability conditions
known deprecations
fallback path
```

## 19.3 Research log

Create:

```text
docs/research/
├── apple-api-decisions.md
├── dependency-decisions.md
├── claude-code-decisions.md
└── open-questions.md
```

Do not turn research notes into a giant permanent prompt. Store durable facts in the appropriate documentation and keep `CLAUDE.md` focused on decisions that Claude should consistently obey.

---

# 20. Research-Informed Changes from the Prior Executive Summary

The earlier research surfaced several useful principles that are now incorporated into this master specification.

## 20.1 Adopted

- Feature-oriented architecture instead of view-model proliferation.
- Clean separation between UI, deterministic domain logic, persistence, and optional integrations.
- Integer minor-unit storage for money.
- Structured concurrency and actor isolation.
- Explicit recurrence engine and migration strategy.
- Native Apple frameworks wherever possible.
- Swift Testing for new unit/domain tests with XCTest retained for UI/performance.
- Local profiling and Instruments instead of paid observability tools.
- `CLAUDE.md`, Skills, Hooks, subagents, and MCP as project-level Claude Code infrastructure.
- Small, reusable agent workflows rather than one giant prompt.
- Test/verify loops as part of the coding-agent contract.
- Security boundaries around secrets and OAuth credentials.

## 20.2 Deliberately not adopted as defaults

The research report named several third-party libraries and cloud services. They are not defaults here because they are unnecessary for the current product or conflict with the project's privacy/cost constraints:

- Alamofire
- Resolver/Swinject
- Realm
- Moya
- Firebase Analytics
- Firebase Crashlytics
- Sentry
- Amplitude
- Kingfisher
- third-party chart libraries
- generic DI frameworks
- third-party OCR/cloud AI services
- Slack/Jira/Google Drive MCPs

The project should add any of these only when a concrete engineering problem justifies the dependency.

## 20.3 Corrected from earlier research material

The earlier Executive Summary contained some older or overly generic implementation assumptions. They are intentionally corrected here:

- Do not hard-code obsolete Claude model names or old Claude Code commands. The project should use the current installed Claude Code version and documented command set. For example, current Claude Code documentation describes `/run`, `/verify`, `/doctor`, skills, MCP management, and current CLI installation paths.
- Do not configure an Anthropic API key merely because an API-based setup exists. The project's paid Claude subscription is the intended Claude Code access path.
- Do not assume GitHub Actions, Firebase, Sentry, or another free-tier cloud product is automatically appropriate simply because its free tier exists.
- Do not describe widgets or App Groups as universally available under free personal provisioning. Treat physical-device entitlement availability as a separate constraint and keep the core app independent of it.
- Do not describe Foundation Models as a generic paid cloud LLM facility. Use the on-device model for v1 and keep cloud-model support out of the core product. Apple's current framework also supports broader model integration, but that is not needed for this project.
- Do not retain the research report's iOS 17 / Swift 5.9-era framing. This project remains explicitly targeted at iOS 26+ and the current compatible Swift/Xcode toolchain.

---

# 21. Immediate Claude Code Implementation Order

When implementation begins, Claude Code should execute the project in this order:

```text
Phase 0 — Environment
    Audit Xcode / Swift / Simulator / Claude Code / Git
    Create CLAUDE.md
    Create .claude/settings.json
    Create skills
    Create Scripts/

Phase 1 — Skeleton
    Create Xcode project/targets
    Establish SwiftData model container
    Establish feature/core module boundaries
    Establish test targets
    Establish formatting and local verify script

Phase 2 — Domain foundation
    Money
    Currency
    Transactions
    Categories
    Recurrence engine
    Balance calculations

Phase 3 — Core UX
    Quick Add
    Transaction list/detail
    Dashboard
    Category management

Phase 4 — Wishlist
    Wishlist CRUD
    Purchase conversion
    Linked transaction integrity

Phase 5 — Tasks
    Kanban columns
    Task items
    Subtasks
    Drag/reorder/accessibility alternatives

Phase 6 — Analytics
    Deterministic calculations
    Charts
    Filters
    Narratives only after deterministic analytics are stable

Phase 7 — Backup/export
    Versioned backup
    Restore validation
    CSV
    Optional Google Sheets integration

Phase 8 — Intelligence
    Foundation Models integration
    Natural-language drafting
    Categorization
    Receipt/image assistance
    Regression fixtures

Phase 9 — Optional system surfaces
    App Intents
    Widget extension
    App Group path when provisioning is available

Phase 10 — Hardening
    Migration tests
    Accessibility audit
    Performance audit
    Privacy review
    Data-loss/destructive-action review
    Full verification suite
```

Claude Code should not jump to later phases simply because the framework is technically available. The deterministic, local core is the foundation.

---

# 22. Research References

The implementation agent should consult current primary documentation before making version-sensitive decisions. Key references used to update this specification include:

- Apple Developer — Developer account overview and Personal Team provisioning: https://developer.apple.com/help/account/basics/about-your-developer-account
- Apple Developer — Programs overview and membership requirements: https://developer.apple.com/help/account/membership/programs-overview
- Apple Developer — App Groups entitlement: https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.application-groups
- Apple Developer — WidgetKit strategy: https://developer.apple.com/documentation/WidgetKit/Developing-a-WidgetKit-strategy
- Apple Developer — Widget extensions: https://developer.apple.com/documentation/WidgetKit/Creating-a-Widget-Extension
- Apple Developer — Foundation Models updates: https://developer.apple.com/documentation/updates/foundationmodels
- Apple Developer — Apple Intelligence: https://developer.apple.com/apple-intelligence/
- Apple Developer — Swift Testing: https://developer.apple.com/documentation/Testing
- Apple Developer — XCTest: https://developer.apple.com/documentation/xctest/
- Anthropic — Claude Code Overview: https://code.claude.com/docs/en/overview
- Anthropic — Claude Code Skills: https://code.claude.com/docs/en/skills
- Anthropic — Claude Code MCP: https://code.claude.com/docs/en/mcp
- Anthropic — Claude Code Hooks: https://code.claude.com/docs/en/hooks
- Anthropic — Claude model lifecycle/deprecations: https://docs.anthropic.com/en/docs/about-claude/model-deprecations

These references should be re-checked whenever a proposed implementation depends on an entitlement, a new Apple framework, a new Claude Code feature, or a third-party package version.

---

# 23. Audit Pass — Corrections and Gaps (v3.1)

An audit of v3.0 before handing this document to a coding agent found two defects and five gaps significant enough to cause rework or ambiguous-implementation risk. Corrections are already applied above; gaps are closed in §24–§29.

## 23.1 Defects corrected

| Defect | Impact if unfixed | Fix |
|---|---|---|
| Unterminated ` ```text ` fence in §10.3 (`HouseholdCalendar` operations list) | Every Markdown renderer would misparse roughly half the remaining document (headers, tables, and prose inside §11 onward would intermittently render as literal code or lose structure), and a coding agent reading the raw file could misjudge where instructions end and illustrative code begins | Closed the fence |
| `AppSettings.AIInsightsEnabled` used PascalCase while every sibling property uses camelCase | A literal implementation would either produce an inconsistent Swift property name or force the agent to silently "correct" the spec, which is exactly the kind of undocumented judgment call this project is trying to avoid | Renamed to `aiInsightsEnabled` |

## 23.2 Gaps closed

| Gap | Why it matters | Where it's closed |
|---|---|---|
| The document's own title promises a "UX ... Specification," but no section defines navigation structure, screen composition, or widget/Analytics content | An agent given only "Dashboard screen" as a scope item will invent layout, navigation pattern, and information hierarchy from scratch — the single biggest source of rework and back-and-forth for a UI-heavy app | §24 |
| Principle A ("`47.50 coffee` should be enough") and §12.5 ("AI unavailable → deterministic parser") both assume a deterministic Quick Add parser exists, but nothing specifies its grammar | Without a defined grammar, the agent must guess what "deterministic" parsing means, and that guess will not match what AI-assisted parsing is later expected to extend | §25 |
| §7.12 and §15 reference a "versioned, portable backup format" but never show its shape | Backup/restore is explicitly called out in the Definition of Done (§18) as a change requiring extra scrutiny; an undefined schema means the agent designs it once for implementation and likely redesigns it once someone actually reviews it | §26 |
| No numeric performance targets exist anywhere, despite §5.4 giving qualitative query guidance ("keep UI result sets bounded") | "Bounded" isn't testable; the agent has no threshold to write a performance test against, so `[ ] Reduce Motion behavior checked`-style Definition of Done items in §18 have no equivalent for performance | §27 |
| §21 gives a 10-phase build order but no rule preventing the agent from starting Phase *N+1* while Phase *N* has unresolved verification failures | Agentic coding sessions drift forward under momentum; without an explicit gate, partially-broken foundations compound | §28 |
| The spec is ~2,000 lines and is meant to be read by Claude Code at the start of sessions, but §15.3 already warns against putting "long procedural checklists" in `CLAUDE.md` | Handing the full file to the agent every session burns context on sections irrelevant to the current phase (e.g., full AI regression-fixture detail while building the Dashboard) | §29 |

---

# 24. UX: Navigation and Screen Specifications

This section defines the information architecture the earlier sections assumed but never stated. Treat it as binding for Phase 3 onward; the agent should not invent a different navigation pattern.

## 24.1 Navigation structure

Use a standard iOS tab bar, not a custom navigation shell:

```text
TabView
├── Dashboard      (house icon)
├── Budget         (dollar/list icon)
├── Wishlist       (heart/star icon)
├── Tasks          (checklist icon)
└── More           (ellipsis) → Analytics, Settings
```

Rationale: five items is the platform-idiomatic ceiling before iOS collapses extras into "More." Analytics is used less often than the first four, so it belongs behind "More" alongside Settings rather than consuming a primary tab slot.

Each tab owns its own `NavigationStack`. Quick Add is not a tab; it is a persistent floating action (§24.3).

## 24.2 Screen-by-screen composition

| Screen | Primary content, top to bottom | Key interactions |
|---|---|---|
| Dashboard | Current balance (large), pending impact, 30-day projected balance, "this week" spending snapshot, upcoming recurring items (next 7 days), recent activity (last 5 transactions/tasks/wishlist changes) | Tap any summary card to deep-link into the owning tab's filtered view |
| Budget | Segmented control: Transactions / Recurring, filter bar (period, category, status), grouped list (by day) | Swipe-to-edit/delete on a row; pull to reveal Quick Add |
| Wishlist | Filter chips (priority, status), grid or list toggle, item cards with image thumbnail, priority, estimated price | Tap item → detail with "Mark Purchased" flow (§8.1) |
| Tasks | Kanban board, horizontally scrollable columns | Drag-and-drop reorder/move between columns; every drag interaction has a non-drag accessibility alternative (§24.5) |
| Analytics | Period selector, spending-by-category chart, income-vs-expense trend chart, top merchants list, optional AI narrative summary (collapsed by default, never auto-generated on screen open if AI is disabled) | Tap a category slice to filter Budget tab to that category |
| Settings | Currency, categories (list, add, edit, archive, reassign — §8.4), Face ID toggle, AI feature toggles (each independently switchable), backup/restore, CSV/Google Sheets export, appearance, about | Categories: swipe and context-menu archive/edit/delete; deleting a referenced category offers archive or move-then-delete |
| Onboarding (first launch only) | Currency, starting balance, as-of date (§9.1) | Shown until setup completes; cannot be dismissed without it. Added 2026-09-25 (Sprint 2) because balances need a currency and starting balance and no screen captured them |

Do not add screens or navigation levels beyond what's listed without updating this table — an agent that discovers a "need" for an extra screen mid-implementation should treat that as a signal to re-read this section, not to design ad hoc.

## 24.3 Quick Add

Quick Add is a modal sheet reachable from every tab via a persistent floating button (bottom-right, standard iOS placement) and from the Dashboard's primary card.

```text
Quick Add sheet
├── Single text field (autofocused), parsed per §25
├── Type segmented control: Expense / Income / Wishlist item / Task
├── Progressive disclosure: category, date, notes appear only after
│   the text field yields a valid parse, or on manual "Add details" tap
└── Save button (disabled until a valid draft exists)
```

## 24.4 Widget content

Two widget sizes ship in v1; do not add more without a documented reason.

| Size | Content |
|---|---|
| Small | Current balance + one-line pending impact |
| Medium | Current balance, projected 30-day balance, next 2 upcoming recurring items |

Both sizes include a Quick Add deep-link button (App Intent-backed). Under the free-provisioning constraint (§5.2, §11.2), widgets read `FreeDevelopmentWidgetDataProvider` fixture data in simulator/preview builds and only read live App Group data once that entitlement is available — the widget's visual design must not visibly differ between the two data sources.

## 24.5 Accessibility-specific interaction requirements

- Kanban drag-and-drop (Tasks) must have a non-drag alternative: a context menu or "Move to..." action sheet reachable via VoiceOver and Switch Control.
- Swipe actions (Budget row edit/delete) must have equivalent context-menu actions.
- Every icon-only control (tab bar icons, floating Quick Add button) requires an accessibility label distinct from its visual tooltip if any.
- Charts (Analytics) must expose underlying data via `AXChartDescriptor` or an equivalent accessible data table, not only as a rendered image.

---

# 25. Deterministic Quick Add Parsing Grammar

This defines the non-AI baseline parser referenced by Principle A and §12.5, so "deterministic fallback" is an implementable spec rather than a placeholder.

## 25.1 Grammar (v1)

```text
[amount] [merchant/description text]
[amount] [merchant/description text] #[category]
[+|income] [amount] [description text]
[amount] [description] [relative-date keyword]
```

Examples:

```text
47.50 coffee              → expense, 47.50, notes: "coffee"
+ 1200 paycheck            → income, 1200.00, notes: "paycheck"
32.10 groceries #food      → expense, 32.10, category match: "food" (fuzzy, case-insensitive)
18 lunch yesterday         → expense, 18.00, occurredAt: yesterday's date
```

## 25.2 What the deterministic parser extracts

```text
amount        required; first parseable number, decimal or integer
type          expense by default; income if a leading "+" or the word
              "income"/"received" is present
description   remaining free text after amount/keywords are stripped
category      only if an explicit #tag matches an existing category
              name (case-insensitive substring match); otherwise omitted
date          only from a small fixed vocabulary: "today," "yesterday,"
              weekday names (nearest past occurrence); otherwise defaults
              to now
```

## 25.3 What the deterministic parser never guesses

```text
Merchant normalization beyond exact/substring category-name matching
Category inference from description semantics ("coffee" → Dining)
Multi-currency detection
Recurrence detection from phrasing ("every month")
```

These remain AI-assisted-only capabilities (§12.3). When AI is disabled, the user fills them in manually via the progressive-disclosure fields in §24.3 — this is the concrete mechanism behind "the underlying application must remain completely correct with every AI feature disabled" (Principle B).

## 25.4 Failure behavior

If no amount can be parsed, Quick Add does not error — it simply leaves the amount field empty and lets the user fill in the structured fields directly. The free-text field is always an optional accelerator, never a required syntax the user must learn.

---

# 26. Backup DTO Schema (v1)

Concrete shape for the "versioned, portable backup format" required by §7.12 and the Definition of Done (§18).

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-09-25T10:00:00Z",
  "appVersion": "1.0.0",
  "settings": { "...": "AppSettings fields, minus any secret/token data" },
  "categories": [ { "id": "uuid", "...": "..." } ],
  "merchants": [ { "id": "uuid", "...": "..." } ],
  "transactions": [ { "id": "uuid", "...": "..." } ],
  "recurringTransactions": [ { "id": "uuid", "...": "..." } ],
  "wishlistItems": [ { "id": "uuid", "...": "..." } ],
  "boardColumns": [ { "id": "uuid", "...": "..." } ],
  "taskItems": [ { "id": "uuid", "...": "..." } ],
  "subtaskItems": [ { "id": "uuid", "...": "..." } ],
  "mediaManifest": [
    { "reference": "Wishlist/xyz.jpg", "sizeBytes": 12345 }
  ]
}
```

## 26.1 Rules

- `schemaVersion` is an integer, incremented on any breaking field change. Never reuse a version number for an incompatible shape.
- The backup file never embeds image binaries inline; `mediaManifest` lists references, and media files ship alongside the JSON in a zip/bundle. Restore must fail gracefully (not corrupt existing data) if referenced media is missing.
- No Keychain-stored secret (Google OAuth tokens, biometric config) is ever included.
- Restore is transactional: validate the entire file against the current schema version (including any migration from an older `schemaVersion`) before writing anything, so a malformed backup cannot leave a half-restored store — this is the backup-side application of the same atomicity rule §8.1 requires for wishlist purchases.
- A restore that would overwrite existing data requires explicit user confirmation and states whether it merges or replaces.

---

# 27. Non-Functional Performance Budgets

Concrete, testable thresholds for the qualitative guidance in §5.4 and elsewhere. Use these as target values in performance tests (§13.2), not as hard release blockers if the underlying hardware can't reasonably hit them — but any miss should be an explicit, documented decision, not silence.

| Scenario | Budget |
|---|---|
| Cold launch to interactive Dashboard | Under 2 seconds on the reference device (iPhone 16 Pro Max simulator) |
| Budget list scroll, 5,000+ transactions | No dropped-frame stutter under normal scroll velocity; list is paginated/windowed per §5.4, never loading the full history into memory |
| Quick Add: text entry to parsed draft | Under 150ms perceived latency (parsing is synchronous and local, so this should be trivial — a regression here signals accidental main-thread blocking) |
| Analytics recompute on period change | Under 1 second for a household with 5 years of transaction history |
| Wishlist purchase conversion (§8.1) | Atomic write completes without a visible loading state in the common case |

---

# 28. Phase Gates (Definition of Ready)

§21 defines the build order. This section makes it a hard sequencing rule rather than a suggestion: **Claude Code must not begin work on Phase N+1 until Phase N satisfies every applicable item in the Definition of Done (§18) and `Scripts/verify.sh` passes.**

If a later phase surfaces a defect in an earlier phase's foundation (for example, Phase 4's wishlist-purchase flow reveals a bug in Phase 2's balance calculator), fix it as a Phase-2-scoped change and rerun that phase's verification before continuing — do not patch around it in the later phase's code. This keeps each phase an honest checkpoint rather than a label.

Before starting a phase, the agent should state in its plan which prior phase it's building on and confirm (from its own verification run, not from memory of having said so earlier) that phase is still green.

---

# 29. Document Modularization for Token-Efficient Agent Sessions

This file is ~2,000 lines. §15.3 already warns against stuffing long procedural material into `CLAUDE.md`; the same logic applies to this master spec once implementation starts — most sessions only need one or two sections of it.

## 29.1 Recommended split

Before starting Phase 0, break this file into:

```text
docs/spec/
├── 00-index.md              # one-paragraph summary of each section below,
│                             #   with a pointer to which phase needs it
├── 01-vision-and-scope.md   # §1–2
├── 02-architecture.md       # §3–5
├── 03-domain-and-money.md   # §6–10
├── 04-zero-cost-and-ai.md   # §11–12
├── 05-testing-and-ci.md     # §13–14
├── 06-claude-code-ops.md    # §15–19, §28–29
├── 07-ux-and-screens.md     # §24
├── 08-parsing-and-backup.md # §25–26
└── 09-nfrs.md               # §27
```

Keep this original file (`Household_Hub_iOS_App_Specs_Enhanced_v3.md`) as the archival source of truth, but have Claude Code's first session (§16.2) perform the split and have `CLAUDE.md` reference `docs/spec/00-index.md` rather than the full document.

## 29.2 Session-loading rule

For any given task, the agent should read `00-index.md` plus only the specific numbered file(s) relevant to that task — e.g., a Dashboard UI task reads `02-architecture.md` and `07-ux-and-screens.md`, not `04-zero-cost-and-ai.md` or `08-parsing-and-backup.md`. This is a direct token-cost reduction with no loss of correctness, since the content is unchanged — only how much of it loads into a given session's context.
