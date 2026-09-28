import Foundation
import HouseholdHubCore
import SwiftData
import Testing

@testable import HouseholdHub

/// Sprint 23: the Budget list's Uncategorized filter (A-006), bulk actions (A-007) and the editor's "changed" check
/// (A-015).
struct Sprint23ListTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func record(
        _ type: TransactionType, categoryID: UUID? = nil, merchant: String? = nil, notes: String? = nil
    ) -> TransactionRecord {
        let record = TransactionRecord(
            amount: cad(1_250), type: type, status: .posted, source: .manual, occurredAt: now.addingTimeInterval(-60),
            now: now)
        record.categoryID = categoryID
        record.merchantNameSnapshot = merchant
        record.notes = notes
        return record
    }

    private func category(_ name: String, kind: CategoryKind, archived: Bool = false) -> CategoryRecord {
        let category = CategoryRecord(
            name: name, icon: "tag", color: ColorToken(red: 20, green: 90, blue: 160), kind: kind, sortOrder: 0,
            now: now)
        category.isArchived = archived
        return category
    }

    // MARK: Uncategorized filter (A-006)

    @Test func categoryChoiceReadsBackWhatWasChosen() {
        let dining = UUID()
        for choice in [TransactionFilter.CategoryChoice.all, .uncategorized, .category(dining)] {
            var filter = TransactionFilter()
            filter.categoryChoice = choice
            #expect(filter.categoryChoice == choice)
        }
        var filter = TransactionFilter(categoryID: dining)
        filter.categoryChoice = .uncategorized
        #expect(filter.categoryID == nil, "Uncategorized replaces a chosen category")
        #expect(filter.isActive)
        filter.categoryChoice = .all
        #expect(!filter.isActive, "All categories clears the category part of the filter")
    }

    @Test func uncategorizedListsTransactionsWithoutACategoryButNoTransfers() throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        let dining = UUID()
        let plain = record(.expense)
        let filed = record(.expense, categoryID: dining)
        let paycheck = record(.income)
        let refund = record(.refund)
        let transfer = record(.transfer)
        for item in [plain, filed, paycheck, refund, transfer] {
            context.insert(item)
        }
        try context.save()

        func fetch(_ choice: TransactionFilter.CategoryChoice) throws -> Set<UUID> {
            var filter = TransactionFilter()
            filter.categoryChoice = choice
            return Set(try context.fetch(filter.fetchDescriptor(now: now, calendar: calendar)).map(\.id))
        }

        #expect(try fetch(.uncategorized) == [plain.id, paycheck.id, refund.id])
        #expect(try fetch(.category(dining)) == [filed.id])
        #expect(try fetch(.all) == [plain.id, filed.id, paycheck.id, refund.id, transfer.id])
    }

    // MARK: Bulk actions (A-007)

    @Test(arguments: [
        (TransactionType.expense, true), (.income, true), (.transfer, false), (.refund, false),
    ])
    func onlyExpensesAndIncomeAreRecategorized(type: TransactionType, expected: Bool) {
        #expect(BulkEdit.canSetCategory(type) == expected)
    }

    @Test func bulkCategoriesAreActiveAndAllowEverySelectedType() {
        let groceries = category("Groceries", kind: .expense)
        let salary = category("Salary", kind: .income)
        let misc = category("Misc", kind: .both)
        let old = category("Old", kind: .both, archived: true)
        let all = [groceries, salary, misc, old]
        #expect(BulkEdit.categories(all, for: [.expense]).map(\.name) == ["Groceries", "Misc"])
        #expect(BulkEdit.categories(all, for: [.income]).map(\.name) == ["Salary", "Misc"])
        #expect(BulkEdit.categories(all, for: [.expense, .income]).map(\.name) == ["Misc"])
    }

    @Test func bulkDraftChangesOnlyTheCategory() {
        let dining = UUID()
        let original = record(.expense, merchant: "Corner Café", notes: "Lunch")
        original.accountID = UUID()
        let draft = BulkEdit.draft(original, categoryID: dining)
        #expect(draft.categoryID == dining)
        #expect(draft.amount == original.amount)
        #expect(draft.type == original.type)
        #expect(draft.status == original.status)
        #expect(draft.occurredAt == original.occurredAt)
        #expect(draft.merchantName == "Corner Café")
        #expect(draft.notes == "Lunch")
        #expect(draft.accountID == original.accountID)
        #expect(!draft.isAIClassified)
    }

    @Test func refundsAreDeletedBeforeTheirPurchases() {
        let purchase = record(.expense)
        let refund = record(.refund)
        let paycheck = record(.income)
        let ordered = BulkEdit.deletionOrder([purchase, paycheck, refund]).map(\.id)
        #expect(ordered == [refund.id, purchase.id, paycheck.id])
    }

    /// The bulk path is the single-edit path: the service accepts the draft, keeps the merchant, and a purchase
    /// selected with its refund can be deleted once the refund goes first.
    @Test func bulkEditsGoThroughTheServiceRules() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(100_000), asOf: now.addingTimeInterval(-86_400), now: now)
        let dining = try await categories.create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)

        let purchaseID = try await ledger.create(
            TransactionDraft(amount: cad(4_000), type: .expense, occurredAt: now, merchantName: "Corner Café"),
            now: now)
        func stored(_ id: UUID) throws -> TransactionRecord {
            let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }
        let purchase = try stored(purchaseID)
        try await ledger.update(purchaseID, with: BulkEdit.draft(purchase, categoryID: dining), now: now)
        #expect(try stored(purchaseID).categoryID == dining)
        #expect(try stored(purchaseID).merchantNameSnapshot == "Corner Café")

        try await ledger.refundTransaction(
            purchaseID, amount: cad(1_000), occurredAt: now, notes: nil, calendar: calendar, now: now)
        let both = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(both.count == 2)
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await ledger.deleteTransaction(purchaseID, alsoDisableSeries: false, now: now)
        }
        for record in BulkEdit.deletionOrder(both) {
            try await ledger.deleteTransaction(record.id, alsoDisableSeries: false, now: now)
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>()).isEmpty)
    }

    // MARK: Editor changes (A-015)

    @Test func anUntouchedEditorHasNoChanges() {
        let stored = record(.expense, merchant: "Corner Café", notes: "Lunch")
        let untouched = TransactionEdits(
            type: .expense, amount: stored.amount, occurredAt: stored.occurredAt, status: .posted, categoryID: nil,
            merchant: "Corner Café ", notes: " Lunch", accountID: nil)
        #expect(untouched == TransactionEdits(record: stored), "Surrounding spaces are not a change")
        let empty = record(.expense)
        let blank = TransactionEdits(
            type: .expense, amount: empty.amount, occurredAt: empty.occurredAt, status: .posted, categoryID: nil,
            merchant: "  ", notes: "", accountID: nil)
        #expect(blank == TransactionEdits(record: empty), "An empty field is the same as none")
    }

    enum EditedField: CaseIterable, Sendable {
        case amount
        case unreadableAmount
        case type
        case date
        case status
        case category
        case merchant
        case notes
        case account
    }

    @Test(arguments: EditedField.allCases)
    func anyEditedFieldIsAChange(_ field: EditedField) {
        let stored = record(.expense, merchant: "Corner Café", notes: "Lunch")
        let base = TransactionEdits(record: stored)
        var edit = base
        switch field {
        case .amount: edit.amount = cad(1_300)
        case .unreadableAmount: edit.amount = nil
        case .type: edit.type = .income
        case .date: edit.occurredAt = stored.occurredAt.addingTimeInterval(-86_400)
        case .status: edit.status = .pending
        case .category: edit.categoryID = UUID()
        case .merchant: edit.merchant = "Bakery"
        case .notes: edit.notes = "Dinner"
        case .account: edit.accountID = UUID()
        }
        #expect(edit != base)
    }
}
