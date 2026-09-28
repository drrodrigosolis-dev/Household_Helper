import CoreData
import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23 (F3): undo gives back exactly what a delete or a bulk category edit changed (same ids, every field, the
/// links and the linked state), in one save, and refuses cleanly, changing nothing, once that is no longer possible.
struct TransactionUndoTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    private let calendar = TransactionUndoTests.calendar
    /// Sunday 2026-09-27, noon in Vancouver.
    private let now: Date = TransactionUndoTests.date(2026, 9, 27)
    /// When the delete and the undo happen, so an update time the delete changed must be put back.
    private var later: Date { now.addingTimeInterval(120) }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func cad(_ minorUnits: Int64) -> Money { Money(minorUnits: minorUnits, currencyCode: "CAD") }

    /// A wishlist item's purchase state, as a value.
    private struct ItemState: Equatable {
        let status: String
        let purchasedTransactionID: UUID?
        let actualPriceMinorUnits: Int64?
        let updatedAt: Date
    }

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let board: TaskBoardService
        let shopping: UUID

        func record(_ id: UUID) throws -> TransactionRecord? {
            let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
            return try ModelContext(container).fetch(descriptor).first
        }

        func snapshot(_ id: UUID) throws -> TransactionSnapshot {
            TransactionSnapshot(of: try #require(try record(id)))
        }

        func item(_ id: UUID) throws -> ItemState {
            let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id })
            let item = try #require(try ModelContext(container).fetch(descriptor).first)
            return ItemState(
                status: item.statusRawValue, purchasedTransactionID: item.purchasedTransactionID,
                actualPriceMinorUnits: item.actualPriceMinorUnits, updatedAt: item.updatedAt)
        }

        func series(_ id: UUID) throws -> RecurringTransaction {
            let descriptor = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }

        func task(_ id: UUID) throws -> TaskItem {
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }

        /// The category the merchant of transaction `id` has learned.
        func learnedCategory(ofMerchantOf id: UUID) throws -> UUID? {
            let merchantID = try #require(try record(id)?.merchantID)
            let descriptor = FetchDescriptor<Merchant>(predicate: #Predicate { $0.id == merchantID })
            return try #require(try ModelContext(container).fetch(descriptor).first).defaultCategoryID
        }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        let board = TaskBoardService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(500_000), asOf: Self.date(2026, 8, 1), now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        let shopping = try await categories.create(
            name: "Shopping", icon: "bag", color: .black, kind: .expense, now: now)
        return Fixture(container: container, ledger: ledger, board: board, shopping: shopping)
    }

    private func balances(_ fixture: Fixture) async throws -> HouseholdBalances {
        try await fixture.ledger.balances(now: now, calendar: calendar, includePendingInProjection: true)
    }

    private func buy(_ minorUnits: Int64, in fixture: Fixture, account: UUID? = nil) async throws -> UUID {
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(minorUnits), type: .expense, occurredAt: Self.date(2026, 9, 20),
                categoryID: fixture.shopping, merchantName: "Corner Store", notes: "Paper", accountID: account),
            now: now)
    }

    // MARK: Delete and undo

    enum Kind: String, CaseIterable, Sendable {
        case plain
        case recurringOccurrence
        case wishlistPurchase
        case refund
    }

    private struct Target {
        let transactionID: UUID
        var seriesID: UUID?
        var itemID: UUID?
        var taskID: UUID?
    }

    private func makeTarget(_ kind: Kind, in fixture: Fixture) async throws -> Target {
        switch kind {
        case .plain:
            let id = try await buy(4_250, in: fixture)
            let task = try await fixture.board.createTask(
                TaskDraft(title: "File the receipt", linkedTransactionID: id), now: now)
            return Target(transactionID: id, taskID: task)
        case .recurringOccurrence:
            let start = Self.date(2026, 9, 1)
            let seriesID = try await fixture.ledger.createSeries(
                templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: calendar.timeZone,
                startDate: start, notes: "Rent", now: now)
            let rule = try fixture.series(seriesID).series()
            let first = RecurrenceEngine().nextOccurrence(of: rule, after: start.addingTimeInterval(-1))
            let occurrence = try #require(first)
            let id = try await fixture.ledger.materialize(seriesID: seriesID, occurrence: occurrence, now: now)
            return Target(transactionID: id, seriesID: seriesID)
        case .wishlistPurchase:
            let item = try await fixture.ledger.createWishlistItem(
                WishlistDraft(name: "Bike", estimatedPrice: cad(25_000)), now: now)
            let id = try await fixture.ledger.purchaseWishlistItem(
                item, actualPrice: cad(24_000), occurredAt: Self.date(2026, 9, 10), categoryID: fixture.shopping,
                now: now)
            return Target(transactionID: id, itemID: item)
        case .refund:
            let purchase = try await buy(6_000, in: fixture)
            let result = try await fixture.ledger.refundTransaction(
                purchase, amount: cad(1_500), occurredAt: Self.date(2026, 9, 21), notes: "Returned one",
                calendar: calendar, now: now)
            return Target(transactionID: result.refundID)
        }
    }

    @Test(arguments: Kind.allCases)
    func undoGivesBackEveryFieldLinkAndBalance(_ kind: Kind) async throws {
        let fixture = try await makeFixture()
        let target = try await makeTarget(kind, in: fixture)
        let id = target.transactionID
        let before = try fixture.snapshot(id)
        let balancesBefore = try await balances(fixture)
        let itemBefore = try target.itemID.map { try fixture.item($0) }
        let seriesUpdatedBefore = try target.seriesID.map { try fixture.series($0).updatedAt }

        let deleted = try await fixture.ledger.deleteTransactionForUndo(
            id, alsoDisableSeries: kind == .recurringOccurrence, now: later)
        #expect(deleted.record == before)
        let balancesDeleted = try await balances(fixture)
        #expect(balancesDeleted != balancesBefore, "The delete changes the figures")
        if kind == .recurringOccurrence {
            #expect(deleted.effect == .markedSkipped)
            #expect(try fixture.record(id)?.status == .cancelled, "An occurrence is kept as skipped")
            #expect(try fixture.series(try #require(target.seriesID)).isEnabled == false)
        } else {
            #expect(deleted.effect == .removed)
            #expect(try fixture.record(id) == nil)
        }
        if let itemID = target.itemID {
            #expect(try fixture.item(itemID).status == WishlistStatus.wanted.rawValue)
        }
        if let taskID = target.taskID {
            #expect(try fixture.task(taskID).linkedTransactionID == nil)
        }

        try await fixture.ledger.undo(.deletion([deleted]), now: later)

        #expect(try fixture.snapshot(id) == before, "Same id and every field as before")
        let balancesAfter = try await balances(fixture)
        #expect(balancesAfter == balancesBefore)
        if let itemID = target.itemID {
            #expect(try fixture.item(itemID) == itemBefore, "The item is purchased by the same record again")
        }
        if let seriesID = target.seriesID {
            let series = try fixture.series(seriesID)
            #expect(series.isEnabled, "The series the delete disabled runs again")
            #expect(series.updatedAt == seriesUpdatedBefore)
        }
        if let taskID = target.taskID {
            #expect(try fixture.task(taskID).linkedTransactionID == id, "The task links to it again")
        }
    }

    /// Bulk delete takes refunds first; one undo brings the purchase and its refund back together.
    @Test func aPurchaseAndItsRefundComeBackTogether() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(6_000, in: fixture)
        let result = try await fixture.ledger.refundTransaction(
            purchase, amount: cad(2_000), occurredAt: Self.date(2026, 9, 22), notes: nil, calendar: calendar,
            now: now)
        let refund = result.refundID
        let before = [try fixture.snapshot(refund), try fixture.snapshot(purchase)]
        let balancesBefore = try await balances(fixture)

        var entries: [DeletedTransaction] = []
        for id in [refund, purchase] {
            entries.append(try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: false, now: later))
        }
        #expect(try fixture.record(purchase) == nil)
        try await fixture.ledger.undo(.deletion(entries), now: later)

        let after = [try fixture.snapshot(refund), try fixture.snapshot(purchase)]
        #expect(after == before)
        let balancesAfter = try await balances(fixture)
        #expect(balancesAfter == balancesBefore)
    }

    /// Bulk delete's "Delete and disable their series" (spec §8.3): two occurrences of one series are skipped and the
    /// series disabled; one undo posts both again and runs the series as it did, with its own update time.
    @Test func occurrencesDeletedWithTheirSeriesDisabledComeBackTogether() async throws {
        let fixture = try await makeFixture()
        let start = Self.date(2026, 8, 5)
        let seriesID = try await fixture.ledger.createSeries(
            templateAmount: cad(9_900), type: .expense, rule: .monthlyOnDay(day: 5), timeZone: calendar.timeZone,
            startDate: start, notes: "Phone", now: now)
        let rule = try fixture.series(seriesID).series()
        let engine = RecurrenceEngine()
        let august = try #require(engine.nextOccurrence(of: rule, after: start.addingTimeInterval(-1)))
        let september = try #require(engine.nextOccurrence(of: rule, after: august))
        var ids: [UUID] = []
        for occurrence in [august, september] {
            ids.append(try await fixture.ledger.materialize(seriesID: seriesID, occurrence: occurrence, now: now))
        }
        let before = try ids.map { try fixture.snapshot($0) }
        let seriesUpdatedBefore = try fixture.series(seriesID).updatedAt
        let balancesBefore = try await balances(fixture)

        var entries: [DeletedTransaction] = []
        for id in ids {
            entries.append(try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: true, now: later))
        }
        #expect(try fixture.series(seriesID).isEnabled == false)
        let skipped = try ids.allSatisfy { try fixture.record($0)?.status == .cancelled }
        #expect(skipped, "Occurrences are kept as skipped")

        try await fixture.ledger.undo(.deletion(entries), now: later)
        let after = try ids.map { try fixture.snapshot($0) }
        #expect(after == before)
        let series = try fixture.series(seriesID)
        #expect(series.isEnabled)
        #expect(series.updatedAt == seriesUpdatedBefore)
        let balancesAfter = try await balances(fixture)
        #expect(balancesAfter == balancesBefore)
    }

    /// Review S6: a transfer comes back with both its accounts.
    @Test func undoGivesBackATransferWithBothAccounts() async throws {
        let fixture = try await makeFixture()
        let savings = try await fixture.ledger.createAccount(
            AccountDraft(
                name: "Savings", kind: .savings, startingBalance: cad(0), startingBalanceDate: Self.date(2026, 8, 1)),
            now: now)
        let id = try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(25_000), type: .transfer, occurredAt: Self.date(2026, 9, 20), transferAccountID: savings),
            now: now)
        let before = try fixture.snapshot(id)
        #expect(before.transferAccountID == savings && before.accountID != nil)
        let balancesBefore = try await balances(fixture)

        let deleted = try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: false, now: later)
        #expect(try fixture.record(id) == nil)
        try await fixture.ledger.undo(.deletion([deleted]), now: later)

        #expect(try fixture.snapshot(id) == before)
        let balancesAfter = try await balances(fixture)
        #expect(balancesAfter == balancesBefore, "Both accounts' figures are as they were")
    }

    /// Review S5: the snapshot names every stored attribute of the current record, so a field added in a later schema
    /// can't be lost on undo without this failing; and every one of them comes back as it was.
    @Test func theSnapshotKeepsEveryStoredField() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [TransactionRecord.self]))
        let entity = try #require(model.entitiesByName["TransactionRecord"])
        let stored = Set(entity.propertiesByName.keys)
        let record = TransactionRecord(
            amount: cad(1_234), type: .refund, status: .pending, source: .manual, occurredAt: now, now: now)
        record.merchantID = UUID()
        record.merchantNameSnapshot = "Corner Store"
        record.categoryID = UUID()
        record.notes = "Paper"
        record.recurringSeriesID = UUID()
        record.scheduledOccurrence = now
        record.wishlistItemID = UUID()
        record.isAIClassified = true
        record.accountID = UUID()
        record.transferAccountID = UUID()
        record.refundOfTransactionID = UUID()
        record.splitGroupID = UUID()
        record.updatedAt = later
        let snapshot = TransactionSnapshot(of: record)
        let fields = Set(Mirror(reflecting: snapshot).children.compactMap(\.label))
        #expect(fields == stored, "Every stored attribute is in the snapshot")
        #expect(TransactionSnapshot(of: snapshot.makeRecord()) == snapshot, "And comes back as it was")
    }

    // MARK: Splits

    /// Splits a 60.00 purchase into 40.00 and 20.00; returns the parts, the original first.
    private func splitParts(in fixture: Fixture) async throws -> (kept: UUID, other: UUID) {
        let original = try await buy(6_000, in: fixture)
        let split = [
            SplitPart(amount: cad(4_000), categoryID: fixture.shopping), SplitPart(amount: cad(2_000), categoryID: nil),
        ]
        let parts = try await fixture.ledger.splitTransaction(original, into: split, now: now)
        #expect(parts.count == 2)
        return (try #require(parts.first), try #require(parts.last))
    }

    @Test func undoOfOnePartOfATwoPartSplitRebuildsTheSplit() async throws {
        let fixture = try await makeFixture()
        let parts = try await splitParts(in: fixture)
        let before = [try fixture.snapshot(parts.kept), try fixture.snapshot(parts.other)]
        #expect(before.allSatisfy { $0.splitGroupID != nil })
        let balancesBefore = try await balances(fixture)

        let deleted = try await fixture.ledger.deleteTransactionForUndo(
            parts.other, alsoDisableSeries: false, now: later)
        #expect(try fixture.record(parts.kept)?.splitGroupID == nil, "The last part left is no longer split")
        try await fixture.ledger.undo(.deletion([deleted]), now: later)

        let after = [try fixture.snapshot(parts.kept), try fixture.snapshot(parts.other)]
        #expect(after == before, "Both parts share their split again, the kept one with its own update time")
        let balancesAfter = try await balances(fixture)
        #expect(balancesAfter == balancesBefore)
    }

    @Test func bothPartsOfASplitComeBackTogether() async throws {
        let fixture = try await makeFixture()
        let parts = try await splitParts(in: fixture)
        let before = [try fixture.snapshot(parts.kept), try fixture.snapshot(parts.other)]

        var entries: [DeletedTransaction] = []
        for id in [parts.other, parts.kept] {
            entries.append(try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: false, now: later))
        }
        try await fixture.ledger.undo(.deletion(entries), now: later)

        let after = [try fixture.snapshot(parts.kept), try fixture.snapshot(parts.other)]
        #expect(after == before)
    }

    /// A part whose split can't be rebuilt (the other part changed since) comes back on its own, unsplit: a lone
    /// part is not a split, and a backup would refuse it.
    @Test func aPartWhoseSplitCantBeRebuiltComesBackUnsplit() async throws {
        let fixture = try await makeFixture()
        let parts = try await splitParts(in: fixture)
        let deleted = try await fixture.ledger.deleteTransactionForUndo(
            parts.other, alsoDisableSeries: false, now: later)
        let kept = try #require(try fixture.record(parts.kept))
        let moved = TransactionDraft(
            amount: kept.amount, type: .expense, occurredAt: Self.date(2026, 9, 24), categoryID: kept.categoryID,
            merchantName: kept.merchantNameSnapshot, notes: kept.notes, accountID: kept.accountID)
        try await fixture.ledger.update(parts.kept, with: moved, now: later)

        try await fixture.ledger.undo(.deletion([deleted]), now: later)
        let restored = try #require(try fixture.record(parts.other))
        #expect(restored.splitGroupID == nil)
        #expect(restored.amountMinorUnits == 2_000, "The money comes back all the same")
        #expect(try fixture.record(parts.kept)?.splitGroupID == nil)
    }

    // MARK: Refusals

    @Test func undoIsRefusedWhenTheAccountIsGone() async throws {
        let fixture = try await makeFixture()
        let cash = try await fixture.ledger.createAccount(
            AccountDraft(
                name: "Cash", kind: .cash, startingBalance: cad(0), startingBalanceDate: Self.date(2026, 8, 1)),
            now: now)
        let id = try await buy(1_000, in: fixture, account: cash)
        let deleted = try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: false, now: later)
        try await fixture.ledger.deleteAccount(cash)

        await #expect(throws: UndoError.linkTargetMissing) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(id) == nil, "Nothing was restored")
    }

    @Test func undoOfARefundIsRefusedWhenItsPurchaseIsGone() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(6_000, in: fixture)
        let result = try await fixture.ledger.refundTransaction(
            purchase, amount: cad(2_000), occurredAt: Self.date(2026, 9, 22), notes: nil, calendar: calendar,
            now: now)
        let refund = result.refundID
        let deleted = try await fixture.ledger.deleteTransactionForUndo(refund, alsoDisableSeries: false, now: later)
        // With its refund gone the purchase can be deleted too, and the refund would point at nothing.
        try await fixture.ledger.deleteTransaction(purchase, alsoDisableSeries: false, now: later)

        await #expect(throws: UndoError.linkTargetMissing) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(refund) == nil)
    }

    /// The draft that saves `record` as it is, to be changed by one field.
    private func unchanged(_ record: TransactionRecord) -> TransactionDraft {
        TransactionDraft(
            amount: record.amount, type: record.type, occurredAt: record.occurredAt, status: record.status,
            categoryID: record.categoryID, merchantName: record.merchantNameSnapshot, notes: record.notes,
            accountID: record.accountID, transferAccountID: record.transferAccountID)
    }

    enum PurchaseDrift: CaseIterable, Sendable {
        case notAnExpense
        case otherAccount
        case laterDay
        case otherCategory
        case otherMerchant
    }

    /// Review B2: a refund comes back only to a purchase it still belongs to, whatever its status; a backup would
    /// refuse any other.
    @Test(arguments: PurchaseDrift.allCases, [false, true])
    func undoOfARefundIsRefusedWhenItsPurchaseNoLongerMatches(drift: PurchaseDrift, cancelled: Bool) async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(6_000, in: fixture)
        let refundDay = Self.date(2026, 9, 21)
        let result = try await fixture.ledger.refundTransaction(
            purchase, amount: cad(1_500), occurredAt: refundDay, notes: nil, calendar: calendar, now: now)
        let refund = result.refundID
        if cancelled {
            try await fixture.ledger.updateRefund(
                refund, amount: cad(1_500), occurredAt: refundDay, status: .cancelled, notes: nil, calendar: calendar,
                now: now)
        }
        let deleted = try await fixture.ledger.deleteTransactionForUndo(refund, alsoDisableSeries: false, now: later)
        var draft = unchanged(try #require(try fixture.record(purchase)))
        switch drift {
        case .notAnExpense:
            draft.type = .income
            draft.categoryID = nil
        case .otherAccount:
            draft.accountID = try await fixture.ledger.createAccount(
                AccountDraft(
                    name: "Cash", kind: .cash, startingBalance: cad(0), startingBalanceDate: Self.date(2026, 8, 1)),
                now: now)
        case .laterDay:
            draft.occurredAt = Self.date(2026, 9, 23)
        case .otherCategory:
            draft.categoryID = try await CategoryService.make(container: fixture.container).create(
                name: "Gifts", icon: "gift", color: .black, kind: .expense, now: now)
        case .otherMerchant:
            draft.merchantName = "Other Shop"
        }
        try await fixture.ledger.update(purchase, with: draft, now: later)

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(refund) == nil, "Nothing was restored")
    }

    enum RefundMisfit: CaseIterable, Sendable {
        case moreThanIsLeft
        case purchaseCancelled
        case purchasePendingWhileRefundPosted
    }

    @Test(arguments: RefundMisfit.allCases)
    func undoOfARefundIsRefusedWhenItNoLongerFits(misfit: RefundMisfit) async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(6_000, in: fixture)
        let result = try await fixture.ledger.refundTransaction(
            purchase, amount: cad(1_500), occurredAt: Self.date(2026, 9, 21), notes: nil, calendar: calendar,
            now: now)
        let refund = result.refundID
        let deleted = try await fixture.ledger.deleteTransactionForUndo(refund, alsoDisableSeries: false, now: later)
        switch misfit {
        case .moreThanIsLeft:
            // 50.00 of 60.00 refunded since: the 15.00 no longer fits in what is left.
            _ = try await fixture.ledger.refundTransaction(
                purchase, amount: cad(5_000), occurredAt: Self.date(2026, 9, 22), notes: nil, calendar: calendar,
                now: later)
        case .purchaseCancelled:
            try await fixture.ledger.setStatus(.cancelled, forTransaction: purchase, now: later)
        case .purchasePendingWhileRefundPosted:
            try await fixture.ledger.setStatus(.pending, forTransaction: purchase, now: later)
        }

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(refund) == nil, "Nothing was restored")
    }

    @Test func undoOfASkippedOccurrenceIsRefusedOnceItIsNoLongerSkipped() async throws {
        let fixture = try await makeFixture()
        let target = try await makeTarget(.recurringOccurrence, in: fixture)
        let seriesID = try #require(target.seriesID)
        let deleted = try await fixture.ledger.deleteTransactionForUndo(
            target.transactionID, alsoDisableSeries: true, now: later)
        try await fixture.ledger.setStatus(.pending, forTransaction: target.transactionID, now: later)

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(target.transactionID)?.status == .pending, "The later edit is kept")
        #expect(try fixture.series(seriesID).isEnabled == false, "Nothing was restored")
    }

    @Test func undoOfAPurchaseIsRefusedOnceTheItemIsBoughtAgain() async throws {
        let fixture = try await makeFixture()
        let target = try await makeTarget(.wishlistPurchase, in: fixture)
        let itemID = try #require(target.itemID)
        let deleted = try await fixture.ledger.deleteTransactionForUndo(
            target.transactionID, alsoDisableSeries: false, now: later)
        let again = try await fixture.ledger.purchaseWishlistItem(
            itemID, actualPrice: cad(23_000), occurredAt: Self.date(2026, 9, 25), categoryID: nil, now: later)

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(target.transactionID) == nil)
        #expect(try fixture.item(itemID).purchasedTransactionID == again, "The new purchase keeps the item")
    }

    @Test func undoTwiceIsRefusedTheSecondTime() async throws {
        let fixture = try await makeFixture()
        let id = try await buy(1_000, in: fixture)
        let deleted = try await fixture.ledger.deleteTransactionForUndo(id, alsoDisableSeries: false, now: later)
        try await fixture.ledger.undo(.deletion([deleted]), now: later)

        await #expect(throws: UndoError.recordAlreadyExists) {
            try await fixture.ledger.undo(.deletion([deleted]), now: later)
        }
        #expect(try fixture.record(id) != nil)
    }

    // MARK: Bulk Set category

    @Test func undoGivesEachTransactionBackItsOwnCategory() async throws {
        let fixture = try await makeFixture()
        let filed = try await buy(1_000, in: fixture)
        let loose = try await fixture.ledger.create(
            TransactionDraft(amount: cad(700), type: .expense, occurredAt: Self.date(2026, 9, 21)), now: now)
        let categories = CategoryService.make(container: fixture.container)
        let dining = try await categories.create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)

        var changes: [CategoryUndoEntry] = []
        for id in [filed, loose] {
            let record = try #require(try fixture.record(id))
            let draft = TransactionDraft(
                amount: record.amount, type: record.type, occurredAt: record.occurredAt, status: record.status,
                categoryID: dining, merchantName: record.merchantNameSnapshot, notes: record.notes,
                accountID: record.accountID)
            changes.append(try await fixture.ledger.updateCategoryForUndo(id, with: draft, now: later))
        }
        #expect(try fixture.record(filed)?.categoryID == dining)
        #expect(changes.map(\.previousCategoryID) == [fixture.shopping, nil])

        try await fixture.ledger.undo(.categoryChange(changes), now: later)
        #expect(try fixture.record(filed)?.categoryID == fixture.shopping)
        #expect(try fixture.record(loose)?.categoryID == nil)
        #expect(try fixture.record(filed)?.merchantNameSnapshot == "Corner Store", "Only the category changes")
    }

    @Test func categoryUndoIsRefusedWhenARecordChangedSince() async throws {
        let fixture = try await makeFixture()
        let id = try await buy(1_000, in: fixture)
        let categories = CategoryService.make(container: fixture.container)
        let dining = try await categories.create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)
        let gifts = try await categories.create(name: "Gifts", icon: "gift", color: .black, kind: .expense, now: now)
        func draft(_ categoryID: UUID) throws -> TransactionDraft {
            let record = try #require(try fixture.record(id))
            return TransactionDraft(
                amount: record.amount, type: .expense, occurredAt: record.occurredAt, categoryID: categoryID,
                merchantName: record.merchantNameSnapshot, notes: record.notes, accountID: record.accountID)
        }
        let change = try await fixture.ledger.updateCategoryForUndo(id, with: try draft(dining), now: later)
        try await fixture.ledger.update(id, with: try draft(gifts), now: later)

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.categoryChange([change]), now: later)
        }
        #expect(try fixture.record(id)?.categoryID == gifts, "A later edit is never overwritten")
    }

    enum PreviousCategoryDrift: CaseIterable, Sendable {
        case archived
        case otherKind
    }

    @Test(arguments: PreviousCategoryDrift.allCases)
    func categoryUndoIsRefusedWhenThePreviousCategoryCantBeUsed(drift: PreviousCategoryDrift) async throws {
        let fixture = try await makeFixture()
        let id = try await buy(1_000, in: fixture)
        let categories = CategoryService.make(container: fixture.container)
        let dining = try await categories.create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)
        var draft = unchanged(try #require(try fixture.record(id)))
        draft.categoryID = dining
        let change = try await fixture.ledger.updateCategoryForUndo(id, with: draft, now: later)
        switch drift {
        case .archived:
            try await categories.setArchived(true, category: fixture.shopping, now: later)
        case .otherKind:
            // Nothing else uses Shopping, so it may become an income category.
            try await categories.update(
                category: fixture.shopping, name: "Shopping", icon: "bag", color: .black, kind: .income, now: later)
        }

        await #expect(throws: UndoError.changedSince) {
            try await fixture.ledger.undo(.categoryChange([change]), now: later)
        }
        #expect(try fixture.record(id)?.categoryID == dining, "Nothing was changed back")
        #expect(try fixture.learnedCategory(ofMerchantOf: id) == dining)
    }

    /// Records the bulk edit's path can no longer write are counted, and the rest is still changed back.
    @Test func categoryUndoReportsWhatItCouldNotChangeBack() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(6_000, in: fixture)
        let result = try await fixture.ledger.refundTransaction(
            purchase, amount: cad(1_000), occurredAt: Self.date(2026, 9, 21), notes: nil, calendar: calendar,
            now: now)
        let other = try await buy(1_000, in: fixture)
        let dining = try await CategoryService.make(container: fixture.container).create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)
        var draft = unchanged(try #require(try fixture.record(other)))
        draft.categoryID = dining
        let changed = try await fixture.ledger.updateCategoryForUndo(other, with: draft, now: later)
        // A refund passes every check (its category is as the entry says), but `update` never writes one: its
        // category follows its purchase. The bulk edit can't produce this entry, so it is made here.
        let unwritable = CategoryUndoEntry(
            transactionID: result.refundID, previousCategoryID: nil, previousIsAIClassified: false,
            appliedCategoryID: fixture.shopping, merchantID: nil, previousMerchantCategoryID: nil,
            appliedMerchantCategoryID: nil)

        await #expect(throws: UndoError.partiallyUndone(failed: 1)) {
            try await fixture.ledger.undo(.categoryChange([changed, unwritable]), now: later)
        }
        #expect(try fixture.record(other)?.categoryID == fixture.shopping, "The rest is changed back")
        #expect(try fixture.record(result.refundID)?.categoryID == fixture.shopping, "The refund keeps its purchase's")
    }

    /// Review S2: the merchant learns the category the bulk edit gave; undo gives it back the one it had learned
    /// before, not merely the record's old category.
    @Test func categoryUndoGivesTheMerchantBackWhatItHadLearned() async throws {
        let fixture = try await makeFixture()
        let categories = CategoryService.make(container: fixture.container)
        let gifts = try await categories.create(name: "Gifts", icon: "gift", color: .black, kind: .expense, now: now)
        let dining = try await categories.create(
            name: "Dining", icon: "fork.knife", color: .black, kind: .expense, now: now)
        let filed = try await buy(1_000, in: fixture)
        // A later purchase at the same store in Gifts: that is what the store has learned.
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(500), type: .expense, occurredAt: Self.date(2026, 9, 21), categoryID: gifts,
                merchantName: "Corner Store"),
            now: now)
        #expect(try fixture.learnedCategory(ofMerchantOf: filed) == gifts)

        var draft = unchanged(try #require(try fixture.record(filed)))
        draft.categoryID = dining
        let change = try await fixture.ledger.updateCategoryForUndo(filed, with: draft, now: later)
        #expect(try fixture.learnedCategory(ofMerchantOf: filed) == dining, "The bulk edit teaches the store")

        try await fixture.ledger.undo(.categoryChange([change]), now: later)
        #expect(try fixture.record(filed)?.categoryID == fixture.shopping)
        #expect(try fixture.learnedCategory(ofMerchantOf: filed) == gifts, "What it had learned before the edit")
    }
}
