import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23 (A-003, A-006): imports keep the description as the merchant, and a merchant learns the category the
/// user files it under by hand, which the import preview and Quick Add then offer as a suggestion.
struct MerchantLearningTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }
    private let cad = try! Currency(code: "CAD")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private struct Stack {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let main: UUID

        func category(_ name: String) throws -> UUID {
            let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
            return try #require(all.first { $0.name == name }).id
        }

        /// The learned category of the merchant `name` names, or nil when there is no such merchant or no category.
        func learned(_ name: String) throws -> UUID? {
            let key = Merchant.normalize(name)
            let merchants = try ModelContext(container).fetch(FetchDescriptor<Merchant>())
            return merchants.first { $0.normalizedName == key }?.defaultCategoryID
        }
    }

    private func makeStack() async throws -> Stack {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let main = try #require(try await ledger.settingsSnapshot()?.defaultAccountID)
        return Stack(container: container, ledger: ledger, categories: categories, main: main)
    }

    @discardableResult
    private func record(
        _ merchant: String?, _ category: UUID?, type: TransactionType = .expense, isAIClassified: Bool = false,
        in stack: Stack
    ) async throws -> UUID {
        let draft = TransactionDraft(
            amount: money(1_250), type: type, occurredAt: day(2026, 9, 1), categoryID: category,
            merchantName: merchant, isAIClassified: isAIClassified)
        return try await stack.ledger.create(draft, now: now)
    }

    // MARK: Learning

    @Test(arguments: [(TransactionType.expense, "Dining"), (.income, "Salary")])
    func aNewEntryTeachesItsMerchant(type: TransactionType, categoryName: String) async throws {
        let stack = try await makeStack()
        let category = try stack.category(categoryName)
        try await record("Café Luna", category, type: type, in: stack)
        #expect(try stack.learned("  cafe LUNA ") == category)
    }

    @Test func changingTheCategoryOrMerchantTeachesButOtherEditsDoNot() async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        let first = try await record("Luna", dining, in: stack)
        try await record("Luna", groceries, in: stack)
        #expect(try stack.learned("Luna") == groceries, "The latest choice wins")

        // Only the amount changes: the older pairing doesn't come back.
        var draft = TransactionDraft(
            amount: money(2_000), type: .expense, occurredAt: day(2026, 9, 1), categoryID: dining,
            merchantName: "Luna")
        try await stack.ledger.update(first, with: draft, now: now)
        #expect(try stack.learned("Luna") == groceries)

        // A new category teaches.
        draft.categoryID = try stack.category("Shopping")
        try await stack.ledger.update(first, with: draft, now: now)
        #expect(try stack.learned("Luna") == draft.categoryID)

        // So does a new merchant for the same category.
        draft.merchantName = "Sol"
        try await stack.ledger.update(first, with: draft, now: now)
        #expect(try stack.learned("Sol") == draft.categoryID)
    }

    enum Unlearned: CaseIterable {
        /// The on-device model's pick is a suggestion, never stored knowledge.
        case modelPick
        /// No category says nothing about the merchant; it doesn't clear what was learned.
        case uncategorized
    }

    @Test(arguments: Unlearned.allCases)
    func someEntriesTeachNothing(_ kind: Unlearned) async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        try await record("Luna", dining, in: stack)
        switch kind {
        case .modelPick: try await record("Luna", groceries, isAIClassified: true, in: stack)
        case .uncategorized: try await record("Luna", nil, in: stack)
        }
        #expect(try stack.learned("Luna") == dining)
    }

    @Test func refundsAndTransfersTeachNothing() async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        let purchase = try await record("Luna", dining, in: stack)
        try await record("Luna", groceries, in: stack)
        try await stack.ledger.refundTransaction(
            purchase, amount: money(500), occurredAt: day(2026, 9, 2), notes: nil, calendar: calendar, now: now)
        #expect(try stack.learned("Luna") == groceries, "A refund follows its purchase; it teaches nothing")

        let account = AccountDraft(
            name: "Savings", kind: .savings, startingBalance: money(0), startingBalanceDate: day(2026, 1, 1))
        let savings = try await stack.ledger.createAccount(account, now: now)
        let transfer = TransactionDraft(
            amount: money(100), type: .transfer, occurredAt: day(2026, 9, 3), accountID: stack.main,
            transferAccountID: savings)
        try await stack.ledger.create(transfer, now: now)
        #expect(try stack.learned("Luna") == groceries)
        #expect(try ModelContext(stack.container).fetchCount(FetchDescriptor<Merchant>()) == 1)
    }

    @Test func quickAddOffersTheLearnedCategoryFirst() async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        try await record("Luna", dining, in: stack)
        try await record("Luna", dining, in: stack)
        try await record("Luna", groceries, in: stack)
        #expect(try await stack.ledger.suggestedCategory(forMerchantText: "luna", type: .expense) == groceries)
    }

    // MARK: Suggestions for an import

    @Test(arguments: ["Café Luna", "  cafe LUNA ", "CAFÉ   luna"])
    func suggestionsMatchNormalizedNames(_ description: String) async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        try await record("Café Luna", dining, in: stack)
        let suggestions = try await stack.ledger.importCategorySuggestions(for: [description, "Unknown"])
        #expect(suggestions == [Merchant.normalize(description): dining])
    }

    @Test func suggestionsSkipArchivedCategories() async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        try await record("Luna", dining, in: stack)
        try await record("Sol", groceries, in: stack)
        try await stack.categories.setArchived(true, category: groceries, now: now)
        let suggestions = try await stack.ledger.importCategorySuggestions(for: ["Luna", "Sol"])
        #expect(suggestions == ["luna": dining])
    }

    private let dining = CSVImportCategory(id: UUID(), name: "Dining", kind: .expense)
    private let salary = CSVImportCategory(id: UUID(), name: "Salary", kind: .income)

    @Test func thePreviewOffersSuggestionsOnlyForRowsTheFileLeftUncategorized() {
        let mapping = CSVMapping(
            columns: [.date: 0, .description: 1, .amount: 2, .category: 3], dateFormat: .yearMonthDay,
            decimalMark: ".", spendingIsPositive: false)
        let rows = [
            ["2026-09-01", "LUNA", "-4.50", ""],  // uncategorized: suggested
            ["2026-09-01", "Luna", "-4.50", "Salary"],  // the file's category doesn't fit: still uncategorized
            ["2026-09-01", "luna", "-4.50", "Dining"],  // the file's own category: no suggestion
            ["2026-09-01", "Luna", "4.50", ""],  // income can't take an expense category
            ["2026-09-01", "Gone", "-4.50", ""],  // learned category no longer offered (archived)
            ["2026-09-01", "Sol", "-4.50", ""],  // nothing learned
        ]
        let records = rows.enumerated().map { CSVRecord(line: $0.offset + 2, fields: $0.element) }
        let preview = CSVImportPlanner.preview(
            records: records, headerCount: 4, mapping: mapping, currency: cad, categories: [dining, salary],
            existing: [], suggestions: ["luna": dining.id, "gone": UUID()], calendar: calendar)
        #expect(preview.map(\.suggestedCategoryID) == [dining.id, dining.id, nil, nil, nil, nil])
        #expect(preview.map { $0.row?.categoryID } == [nil, nil, dining.id, nil, nil, nil], "Rows keep the file's")
    }

    // MARK: Import

    @Test func importAppliesOnlyTheCategoryThePreviewPassesAndTeachesNothing() async throws {
        let stack = try await makeStack()
        let dining = try stack.category("Dining")
        let groceries = try stack.category("Groceries")
        try await record("Luna", dining, in: stack)
        let row = CSVImportRow(
            occurredAt: day(2026, 9, 4), amount: money(450), type: .expense, description: "LUNA", categoryID: nil)
        try await stack.ledger.importTransactions([row, row.filed(under: groceries)], into: stack.main, now: now)
        let imported = try ModelContext(stack.container).fetch(FetchDescriptor<TransactionRecord>())
            .filter { $0.source == .imported }
        #expect(Set(imported.map(\.categoryID)) == [nil, groceries], "No suggestion is applied by the import itself")
        #expect(imported.allSatisfy { $0.merchantNameSnapshot == "LUNA" && $0.notes == nil })
        let merchants = try ModelContext(stack.container).fetch(FetchDescriptor<Merchant>())
        #expect(merchants.count == 1, "The existing merchant is reused")
        #expect(Set(imported.map(\.merchantID)) == [merchants.first?.id])
        #expect(try stack.learned("Luna") == dining, "An import leaves learned categories unchanged")
    }

    @Test func oneMerchantIsMadePerNameInAnImport() async throws {
        let stack = try await makeStack()
        let rows = ["Sol", "  sol ", "SOL", "Luna"].map { description in
            CSVImportRow(
                occurredAt: day(2026, 9, 4), amount: money(450), type: .expense, description: description,
                categoryID: nil)
        }
        try await stack.ledger.importTransactions(rows, into: stack.main, now: now)
        let merchants = try ModelContext(stack.container).fetch(FetchDescriptor<Merchant>())
        #expect(Set(merchants.map(\.normalizedName)) == ["sol", "luna"])
        #expect(merchants.count == 2)
    }

    @Test func theDuplicateCheckStillMatchesImportsThatKeptTheDescriptionInNotes() async throws {
        let stack = try await makeStack()
        // Recorded before Sprint 23: the description in the notes, no merchant.
        let old = TransactionRecord(
            amount: money(450), type: .expense, status: .posted, source: .imported, occurredAt: day(2026, 9, 1),
            now: now)
        old.accountID = stack.main
        old.notes = "Luna"
        let context = ModelContext(stack.container)
        context.insert(old)
        try context.save()
        // Typed in: a merchant and a note.
        let typed = TransactionDraft(
            amount: money(900), type: .expense, occurredAt: day(2026, 9, 1), merchantName: "Sol", notes: "Lunch")
        try await stack.ledger.create(typed, now: now)
        // Imported now: the description is the merchant.
        let row = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(300), type: .expense, description: "Mar", categoryID: nil)
        try await stack.ledger.importTransactions([row], into: stack.main, now: now)

        let existing = try await stack.ledger.existingForImport(
            accountID: stack.main, from: day(2026, 9, 1), to: day(2026, 9, 1), calendar: calendar)
        #expect(Set(existing.compactMap(\.text)) == ["Luna", "Sol", "Lunch", "Mar"])

        let mapping = CSVMapping(
            columns: [.date: 0, .description: 1, .amount: 2], dateFormat: .yearMonthDay, decimalMark: ".",
            spendingIsPositive: false)
        let file = [
            ["2026-09-01", "LUNA", "-4.50"],  // the old import, by its notes
            ["2026-09-01", "sol", "-9.00"],  // the typed-in one, by its merchant
            ["2026-09-01", "Lunch", "-9.00"],  // or by its note
            ["2026-09-01", "Mar", "-3.00"],  // the new import, by its merchant
            ["2026-09-01", "Luna", "-3.00"],  // another amount
        ]
        let records = file.enumerated().map { CSVRecord(line: $0.offset + 2, fields: $0.element) }
        let preview = CSVImportPlanner.preview(
            records: records, headerCount: 3, mapping: mapping, currency: cad, categories: [], existing: existing,
            calendar: calendar)
        #expect(preview.map(\.isLikelyDuplicate) == [true, true, true, true, false])
    }
}
