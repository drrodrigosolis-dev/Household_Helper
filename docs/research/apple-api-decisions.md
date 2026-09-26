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
