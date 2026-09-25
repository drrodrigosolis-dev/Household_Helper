---
name: household-test
description: Design and run Household Hub tests — Swift Testing for domain/service/persistence, XCTest for UI and performance. Use when adding logic, fixing a bug (write the failing test first), or checking coverage of a change.
---

# household-test

## Where tests go
- `HouseholdHubTests/` — Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`). Domain, money,
  recurrence, dates, parsing (§25), backup DTOs (§26), persistence with an in-memory container.
- `HouseholdHubUITests/` — XCTest/XCUIAutomation. Critical flows from §13.2 and performance budgets (§27).
- Never mix Swift Testing and XCTest APIs inside one test.

## Rules
1. Bug fix → first a test that fails for the bug's reason, then the fix.
2. Parameterize (`@Test(arguments:)`) money arithmetic, currency formatting, recurrence (end-of-month, leap
   years, DST in a stored time zone such as America/Vancouver), Quick Add grammar, backup validation.
3. Deterministic: inject clock, calendar, time zone, locale, UUID source. No sleeps; UI waits use
   `waitForExistence`. Accessibility identifiers, not visible strings, for UI queries.
4. Persistence tests use a fresh in-memory `ModelContainer` per test.
5. A test target that executes 0 tests fails CI on purpose (`report_test_counts`).
6. Run: `Scripts/test.sh` / `Scripts/ui-test.sh` on macOS; otherwise `household-verify`. Failures are reported
   with target/test name and message from the `.xcresult`.
