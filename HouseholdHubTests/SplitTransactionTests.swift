import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23 (F4): duplicate a transaction, and split one payment into parts that add up to it exactly (SchemaV4's
/// `splitGroupID`), then merge it back.
struct SplitTransactionTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    private let calendar = SplitTransactionTests.calendar
    /// Sunday 2026-09-27, noon in Vancouver.
    private let now: Date = SplitTransactionTests.date(2026, 9, 27)
    /// When the records being split were entered: before `now`, so the original is the oldest part.
    private let entered: Date = SplitTransactionTests.date(2026, 9, 20)

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let groceries: UUID
        let household: UUID
        let salary: UUID

        func record(_ id: UUID) throws -> TransactionRecord {
            let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }

        func exists(_ id: UUID) throws -> Bool {
            let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
            return try ModelContext(container).fetchCount(descriptor) == 1
        }

        func count() throws -> Int {
            try ModelContext(container).fetchCount(FetchDescriptor<TransactionRecord>())
        }
    }

    private func cad(_ minorUnits: Int64) -> Money { Money(minorUnits: minorUnits, currencyCode: "CAD") }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(100_000), asOf: Self.date(2026, 8, 1), now: entered)
        try await categories.seedSystemCategoriesIfNeeded(now: entered)
        let groceries = try await categories.create(
            name: "Groceries", icon: "cart", color: .black, kind: .expense, now: entered)
        let household = try await categories.create(
            name: "Household", icon: "house", color: .black, kind: .expense, now: entered)
        let salary = try await categories.create(
            name: "Salary", icon: "briefcase", color: .black, kind: .income, now: entered)
        return Fixture(
            container: container, ledger: ledger, groceries: groceries, household: household, salary: salary)
    }

    private func spend(
        _ minorUnits: Int64, status: TransactionStatus = .posted, in fixture: Fixture
    ) async throws -> UUID {
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(minorUnits), type: .expense, occurredAt: Self.date(2026, 9, 10, hour: 8, minute: 30),
                status: status, categoryID: fixture.groceries, merchantName: "Market", notes: "weekly shop"),
            now: entered)
    }

    /// Splits into `amounts`, each part in Groceries unless `categories` names each part's (nil for none).
    @discardableResult
    private func split(
        _ id: UUID, _ amounts: [Int64], categories: [UUID?]? = nil, in fixture: Fixture
    ) async throws -> [UUID] {
        var parts: [SplitPart] = []
        for (index, amount) in amounts.enumerated() {
            let categoryID: UUID? = if let categories { categories[index] } else { fixture.groceries }
            parts.append(SplitPart(amount: cad(amount), categoryID: categoryID))
        }
        return try await fixture.ledger.splitTransaction(id, into: parts, now: now)
    }

    private func balances(_ fixture: Fixture, pending: Bool = false) async throws -> HouseholdBalances {
        try await fixture.ledger.balances(now: now, calendar: calendar, includePendingInProjection: pending)
    }

    // MARK: Duplicate

    @Test(arguments: [TransactionStatus.posted, .pending])
    func aDuplicateCopiesThePaymentDatedTodayAndLinkedToNothing(status: TransactionStatus) async throws {
        let fixture = try await makeFixture()
        let original = try await spend(4_750, status: status, in: fixture)
        let copyID = try await fixture.ledger.duplicateTransaction(original, now: now, calendar: calendar)

        let source = try fixture.record(original)
        let copy = try fixture.record(copyID)
        #expect(copyID != original)
        #expect(copy.amount == cad(4_750))
        #expect(copy.type == .expense)
        #expect(copy.status == status)
        #expect(copy.source == .manual)
        #expect(copy.categoryID == fixture.groceries)
        #expect(copy.merchantID == source.merchantID)
        #expect(copy.merchantNameSnapshot == "Market")
        #expect(copy.notes == "weekly shop")
        #expect(copy.accountID == source.accountID)
        // Today, at the original's time of day (8:30 is already past at noon).
        #expect(copy.occurredAt == Self.date(2026, 9, 27, hour: 8, minute: 30))
        #expect(copy.recurringSeriesID == nil && copy.scheduledOccurrence == nil && copy.wishlistItemID == nil)
        #expect(copy.refundOfTransactionID == nil && copy.splitGroupID == nil)
        #expect(source.occurredAt == Self.date(2026, 9, 10, hour: 8, minute: 30), "The original is untouched")
    }

    @Test func aDuplicateIsNeverDatedInTheFuture() async throws {
        let fixture = try await makeFixture()
        let evening = try await fixture.ledger.create(
            TransactionDraft(amount: cad(900), type: .expense, occurredAt: Self.date(2026, 9, 10, hour: 21)),
            now: entered)
        let copy = try await fixture.ledger.duplicateTransaction(evening, now: now, calendar: calendar)
        #expect(try fixture.record(copy).occurredAt == now)
    }

    @Test func aDuplicateOfAWishlistPurchaseOrASeriesOccurrenceIsAPlainManualEntry() async throws {
        let fixture = try await makeFixture()
        let item = try await fixture.ledger.createWishlistItem(
            WishlistDraft(name: "Lamp", estimatedPrice: cad(5_000)), now: entered)
        let purchase = try await fixture.ledger.purchaseWishlistItem(
            item, actualPrice: cad(4_800), occurredAt: Self.date(2026, 9, 10), categoryID: fixture.household,
            now: entered)
        let copyID = try await fixture.ledger.duplicateTransaction(purchase, now: now, calendar: calendar)
        let copy = try fixture.record(copyID)
        #expect(copy.source == .manual && copy.wishlistItemID == nil && copy.amount == cad(4_800))

        let occurrence = try await occurrenceOfASeries(in: fixture)
        let againID = try await fixture.ledger.duplicateTransaction(occurrence, now: now, calendar: calendar)
        let again = try fixture.record(againID)
        #expect(again.source == .manual && again.recurringSeriesID == nil && again.scheduledOccurrence == nil)
    }

    @Test func aDuplicateOfATransferKeepsBothAccounts() async throws {
        let fixture = try await makeFixture()
        let savings = try await fixture.ledger.createAccount(
            AccountDraft(name: "Savings", kind: .savings, startingBalance: cad(0), startingBalanceDate: entered),
            now: entered)
        let transfer = try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(10_000), type: .transfer, occurredAt: Self.date(2026, 9, 10), transferAccountID: savings),
            now: entered)
        let copyID = try await fixture.ledger.duplicateTransaction(transfer, now: now, calendar: calendar)
        let copy = try fixture.record(copyID)
        let source = try fixture.record(transfer)
        #expect(copy.type == .transfer)
        #expect(copy.accountID == source.accountID && copy.transferAccountID == savings)
    }

    enum Unduplicable: CaseIterable, Sendable {
        case refund
        case cancelled
    }

    @Test(arguments: Unduplicable.allCases)
    func refundsAndCancelledRecordsAreNotDuplicated(kind: Unduplicable) async throws {
        let fixture = try await makeFixture()
        let purchase = try await spend(4_000, in: fixture)
        let target: UUID
        switch kind {
        case .refund:
            let result = try await fixture.ledger.refundTransaction(
                purchase, amount: cad(1_000), occurredAt: now, notes: nil, calendar: calendar, now: now)
            target = result.refundID
        case .cancelled:
            try await fixture.ledger.setStatus(.cancelled, forTransaction: purchase, now: now)
            target = purchase
        }
        let before = try fixture.count()
        await #expect(throws: LedgerError.notDuplicable) {
            try await fixture.ledger.duplicateTransaction(target, now: now, calendar: calendar)
        }
        #expect(try fixture.count() == before)
    }

    // MARK: Split

    @Test func splittingKeepsTheOriginalAsPartOneAndSharesThePayment() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(
            original, [6_000, 4_000], categories: [fixture.groceries, fixture.household], in: fixture)

        #expect(ids.count == 2)
        #expect(ids.first == original)
        let first = try fixture.record(original)
        let second = try fixture.record(ids[1])
        #expect(first.amount == cad(6_000) && first.categoryID == fixture.groceries)
        #expect(second.amount == cad(4_000) && second.categoryID == fixture.household)
        let group = try #require(first.splitGroupID)
        #expect(second.splitGroupID == group)
        #expect(second.type == .expense && second.status == .posted && second.source == first.source)
        #expect(second.occurredAt == first.occurredAt)
        #expect(second.accountID == first.accountID)
        #expect(second.merchantID == first.merchantID && second.merchantNameSnapshot == "Market")
        #expect(second.notes == "weekly shop", "A part without its own note keeps the original's")
        #expect(second.createdAt > first.createdAt)
        #expect(try await fixture.ledger.splitPartIDs(of: ids[1]) == ids)
    }

    @Test(arguments: [TransactionStatus.posted, .pending])
    func splittingNeverChangesABalance(status: TransactionStatus) async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, status: status, in: fixture)
        let before = try await balances(fixture, pending: true)
        _ = try await split(original, [2_500, 2_500, 3_333, 1_667], in: fixture)
        let after = try await balances(fixture, pending: true)
        #expect(after == before)
        #expect(try fixture.count() == 4)
    }

    @Test func anIncomeSplitsToo() async throws {
        let fixture = try await makeFixture()
        let pay = try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(300_000), type: .income, occurredAt: Self.date(2026, 9, 15), categoryID: fixture.salary),
            now: entered)
        let before = try await balances(fixture)
        let ids = try await split(pay, [250_000, 50_000], categories: [fixture.salary, nil], in: fixture)
        #expect(try fixture.record(ids[1]).type == .income)
        #expect(try await balances(fixture) == before)
    }

    enum Unsplittable: CaseIterable, Sendable {
        case transfer
        case refund
        case cancelled
        case recurringOccurrence
        case wishlistPurchase
        case purchaseWithRefunds
        case alreadySplit
    }

    @Test(arguments: Unsplittable.allCases)
    func splittingIsRefused(kind: Unsplittable) async throws {
        let fixture = try await makeFixture()
        let target: UUID
        let expected: LedgerError
        switch kind {
        case .transfer:
            let savings = try await fixture.ledger.createAccount(
                AccountDraft(name: "Savings", kind: .savings, startingBalance: cad(0), startingBalanceDate: entered),
                now: entered)
            target = try await fixture.ledger.create(
                TransactionDraft(
                    amount: cad(10_000), type: .transfer, occurredAt: Self.date(2026, 9, 10),
                    transferAccountID: savings),
                now: entered)
            expected = .notSplittable
        case .refund:
            let purchase = try await spend(10_000, in: fixture)
            let result = try await fixture.ledger.refundTransaction(
                purchase, amount: cad(10_000), occurredAt: now, notes: nil, calendar: calendar, now: now)
            target = result.refundID
            expected = .notSplittable
        case .cancelled:
            target = try await spend(10_000, in: fixture)
            try await fixture.ledger.setStatus(.cancelled, forTransaction: target, now: now)
            expected = .notSplittable
        case .recurringOccurrence:
            target = try await occurrenceOfASeries(amount: 10_000, in: fixture)
            expected = .notSplittable
        case .wishlistPurchase:
            let item = try await fixture.ledger.createWishlistItem(
                WishlistDraft(name: "Lamp", estimatedPrice: cad(10_000)), now: entered)
            target = try await fixture.ledger.purchaseWishlistItem(
                item, actualPrice: cad(10_000), occurredAt: Self.date(2026, 9, 10), categoryID: nil, now: entered)
            expected = .notSplittable
        case .purchaseWithRefunds:
            target = try await spend(10_000, in: fixture)
            _ = try await fixture.ledger.refundTransaction(
                target, amount: cad(1_000), occurredAt: now, notes: nil, calendar: calendar, now: now)
            expected = .purchaseHasRefunds
        case .alreadySplit:
            let original = try await spend(10_000, in: fixture)
            target = try await split(original, [5_000, 5_000], in: fixture)[1]
            expected = .alreadySplit
        }
        let amount = try fixture.record(target).amountMinorUnits
        let before = try fixture.count()
        let parts = [SplitPart(amount: cad(amount - 1), categoryID: nil), SplitPart(amount: cad(1), categoryID: nil)]
        await #expect(throws: expected) {
            try await fixture.ledger.splitTransaction(target, into: parts, now: now)
        }
        #expect(try fixture.count() == before)
        #expect(try fixture.record(target).amountMinorUnits == amount)
    }

    @Test(arguments: [
        ([10_000] as [Int64], LedgerError.splitPartCount),
        (Array(repeating: 1_000 as Int64, count: 11), LedgerError.splitPartCount),
        ([6_000, 3_000], LedgerError.splitDoesNotAddUp),
        ([6_000, 5_000], LedgerError.splitDoesNotAddUp),
        ([10_000, 0], LedgerError.nonPositiveAmount),
        ([12_000, -2_000], LedgerError.nonPositiveAmount),
    ])
    func partsMustBeTwoToTenPositiveAmountsAddingUpExactly(amounts: [Int64], expected: LedgerError) async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        await #expect(throws: expected) {
            try await split(original, amounts, in: fixture)
        }
        let record = try fixture.record(original)
        #expect(record.amount == cad(10_000) && record.splitGroupID == nil)
        #expect(try fixture.count() == 1)
    }

    @Test func tenPartsAreAllowed() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(original, Array(repeating: 1_000, count: 10), in: fixture)
        #expect(Set(ids).count == 10)
    }

    @Test func aPartInAnotherCurrencyOrWithAnIncomeCategoryIsRefused() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await fixture.ledger.splitTransaction(
                original,
                into: [
                    SplitPart(amount: cad(5_000), categoryID: nil),
                    SplitPart(amount: Money(minorUnits: 5_000, currencyCode: "USD"), categoryID: nil),
                ],
                now: now)
        }
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await split(original, [5_000, 5_000], categories: [fixture.groceries, fixture.salary], in: fixture)
        }
        #expect(try fixture.count() == 1)
    }

    @Test(arguments: [
        (10_000 as Int64, [6_000 as Int64, 4_000], 0 as Int64),
        (10_000, [6_000], 4_000),
        (10_000, [], 10_000),
        (10_000, [7_000, 4_000], -1_000),
        (1, [1], 0),
    ])
    func whatIsLeftToAssignIsTheTotalLessTheParts(total: Int64, parts: [Int64], left: Int64) throws {
        #expect(try SplitPart.remaining(of: cad(total), after: parts.map { cad($0) }) == cad(left))
    }

    // MARK: Editing parts

    @Test func editingOnePartsDateStatusOrAccountMovesEveryPart() async throws {
        let fixture = try await makeFixture()
        let card = try await fixture.ledger.createAccount(
            AccountDraft(name: "Card", kind: .creditCard, startingBalance: cad(0), startingBalanceDate: entered),
            now: entered)
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(original, [6_000, 4_000], in: fixture)
        let moved = Self.date(2026, 9, 12)
        try await fixture.ledger.update(
            ids[1],
            with: TransactionDraft(
                amount: cad(4_000), type: .expense, occurredAt: moved, status: .pending, categoryID: fixture.household,
                merchantName: "Corner Store", notes: "cleaning", accountID: card),
            now: now)
        let first = try fixture.record(ids[0])
        let second = try fixture.record(ids[1])
        #expect(first.occurredAt == moved && first.status == .pending && first.accountID == card)
        #expect(first.merchantID == second.merchantID && first.merchantNameSnapshot == "Corner Store")
        #expect(first.categoryID == fixture.groceries && first.notes == "weekly shop", "Each part keeps its own")
        #expect(second.categoryID == fixture.household && second.notes == "cleaning")

        try await fixture.ledger.setStatus(.posted, forTransaction: ids[0], now: now)
        #expect(try fixture.record(ids[1]).status == .posted)
        try await fixture.ledger.setStatus(.cancelled, forTransaction: ids[1], now: now)
        #expect(try fixture.record(ids[0]).status == .cancelled)
    }

    @Test func aPartsTypeDoesNotChange() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(original, [6_000, 4_000], in: fixture)
        await #expect(throws: LedgerError.splitPartsMustAgree) {
            try await fixture.ledger.update(
                ids[1],
                with: TransactionDraft(amount: cad(4_000), type: .income, occurredAt: Self.date(2026, 9, 10)),
                now: now)
        }
        #expect(try fixture.record(ids[1]).type == .expense)
    }

    @Test func deletingAPartLeavesTheOthersSplitUntilOneIsLeft() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(9_000, in: fixture)
        let ids = try await split(original, [3_000, 3_000, 3_000], in: fixture)
        try await fixture.ledger.deleteTransaction(ids[2], alsoDisableSeries: false, now: now)
        #expect(try fixture.record(ids[0]).splitGroupID != nil)
        #expect(try await fixture.ledger.splitPartIDs(of: ids[0]) == Array(ids.prefix(2)))
        try await fixture.ledger.deleteTransaction(ids[1], alsoDisableSeries: false, now: now)
        #expect(try fixture.record(ids[0]).splitGroupID == nil)
        #expect(try fixture.record(ids[0]).amount == cad(3_000), "Deleting is deleting: no amount moves")
    }

    // MARK: Unsplit

    @Test func unsplittingMergesThePartsIntoTheFirst() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        let before = try await balances(fixture)
        let ids = try await split(
            original, [5_000, 3_000, 2_000], categories: [fixture.household, fixture.groceries, nil], in: fixture)
        let board = TaskBoardService.make(container: fixture.container)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        let task = try await board.createTask(TaskDraft(title: "Receipt", linkedTransactionID: ids[2]), now: now)

        // Asked of any part, the merged record is the first.
        let merged = try await fixture.ledger.unsplitTransaction(ids[2], now: now)
        #expect(merged == original)
        let record = try fixture.record(original)
        #expect(record.amount == cad(10_000))
        #expect(record.categoryID == fixture.household, "Part one's category")
        #expect(record.splitGroupID == nil)
        #expect(try !fixture.exists(ids[1]) && !fixture.exists(ids[2]))
        #expect(try fixture.count() == 1)
        #expect(try await balances(fixture) == before)
        let taskID = task
        let byID = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID })
        let linked = try ModelContext(fixture.container).fetch(byID).first?.linkedTransactionID
        #expect(linked == original, "A task linked to a merged part follows the merged record")

        // Split again after merging.
        #expect(try await split(original, [9_000, 1_000], in: fixture).count == 2)
    }

    @Test func unsplitIsRefusedForARecordNotSplitOrAPartWithRefunds() async throws {
        let fixture = try await makeFixture()
        let plain = try await spend(10_000, in: fixture)
        await #expect(throws: LedgerError.notSplit) {
            try await fixture.ledger.unsplitTransaction(plain, now: now)
        }
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(original, [6_000, 4_000], in: fixture)
        _ = try await fixture.ledger.refundTransaction(
            ids[1], amount: cad(1_000), occurredAt: now, notes: nil, calendar: calendar, now: now)
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.checkUnsplit(ids[0])
        }
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.unsplitTransaction(ids[0], now: now)
        }
        #expect(try fixture.exists(ids[1]))
    }

    @Test func unsplitIsRefusedWhenThePartsNoLongerAgree() async throws {
        let fixture = try await makeFixture()
        // Only a store written outside the service can disagree (the service keeps parts in step), so the parts are
        // written directly, on two different days, before the service has read them.
        let context = ModelContext(fixture.container)
        let group = UUID()
        var written: [UUID] = []
        for (amount, day) in [(6_000 as Int64, 10), (4_000, 11)] {
            let part = TransactionRecord(
                amount: cad(amount), type: .expense, status: .posted, source: .manual,
                occurredAt: Self.date(2026, 9, day), now: entered)
            part.splitGroupID = group
            context.insert(part)
            written.append(part.id)
        }
        try context.save()
        let first = try #require(written.first)
        await #expect(throws: LedgerError.splitPartsMustAgree) {
            try await fixture.ledger.unsplitTransaction(first, now: now)
        }
        #expect(try fixture.count() == 2)
    }

    // MARK: Backup

    @Test func aVersion5BackupKeepsEverySplitAndRestoresIt() async throws {
        let fixture = try await makeFixture()
        let original = try await spend(10_000, in: fixture)
        let ids = try await split(original, [6_000, 4_000], in: fixture)
        let backupService = BackupService.make(container: fixture.container)
        let backup = try await backupService.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.schemaVersion == 5)
        let group = try #require(try fixture.record(original).splitGroupID)
        let parts = backup.transactions.filter { $0.splitGroupID == group }.map(\.id)
        #expect(Set(parts) == Set(ids))

        let data = try BackupDTO.encoder().encode(backup)
        #expect(String(data: data, encoding: .utf8)?.contains("\"splitGroupID\"") == true)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: data)
        #expect(decoded == backup)
        try BackupValidator.validate(decoded)

        let fresh = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: fresh).restore(decoded, availableMedia: [], now: now)
        let restored = try await BackupService.make(container: fresh).snapshot(now: now, appVersion: "1") { _ in nil }
        let byID = { (records: [BackupDTO.Transaction]) in records.sorted { $0.id.uuidString < $1.id.uuidString } }
        #expect(byID(restored.transactions) == byID(backup.transactions))
        let freshLedger = TransactionService.make(container: fresh)
        #expect(try await freshLedger.unsplitTransaction(ids[1], now: now) == original)
    }

    @Test func aFileWithoutSplitGroupsStillReads() throws {
        // An absent key reads as not split: every older file.
        let json = """
            {"id":"\(UUID().uuidString)","amountMinorUnits":100,"currencyCode":"CAD","type":"expense",
            "status":"posted","source":"manual","occurredAt":"2026-09-10T19:00:00.000Z","isAIClassified":false,
            "createdAt":"2026-09-10T19:00:00.000Z","updatedAt":"2026-09-10T19:00:00.000Z"}
            """
        let record = try BackupDTO.decoder().decode(BackupDTO.Transaction.self, from: Data(json.utf8))
        #expect(record.splitGroupID == nil)
    }

    @Test(arguments: [1, 2, 3, 4])
    func anOlderFileWithASplitGroupIsRefused(version: Int) async throws {
        let (backup, group) = try await splitBackup(withOthers: false)
        var older = backup
        older.schemaVersion = version
        if version == 1 {
            older.settings.startingBalanceMinorUnits = 0
            older.settings.startingBalanceDate = entered
        }
        let refusal = BackupError.invalidValue(entity: "transactions", field: "splitGroupID", value: group.uuidString)
        #expect(throws: refusal) {
            try BackupValidator.validate(older)
        }
    }

    enum BrokenSplit: CaseIterable, Sendable {
        case lonePart
        case otherDate
        case otherStatus
        case otherAccount
        case otherMerchant
        case onARefund
        case onATransfer
    }

    @Test(arguments: BrokenSplit.allCases)
    func theValidatorRefusesASplitTheAppCouldNotHaveMade(broken: BrokenSplit) async throws {
        let (backup, group) = try await splitBackup()
        var file = backup
        let partIndexes = file.transactions.indices.filter { file.transactions[$0].splitGroupID == group }
        let second = try #require(partIndexes.last)
        switch broken {
        case .lonePart:
            file.transactions[second].splitGroupID = nil
        case .otherDate:
            file.transactions[second].occurredAt = file.transactions[second].occurredAt.addingTimeInterval(60)
        case .otherStatus:
            file.transactions[second].status = TransactionStatus.pending.rawValue
        case .otherAccount:
            let current = file.transactions[second].accountID
            file.transactions[second].accountID = try #require(file.accounts?.first { $0.id != current }?.id)
        case .otherMerchant:
            file.transactions[second].merchantID = nil
        case .onARefund:
            let refund = try #require(file.transactions.firstIndex { $0.type == TransactionType.refund.rawValue })
            file.transactions[refund].splitGroupID = UUID()
            let other = try #require(file.transactions.firstIndex { $0.splitGroupID == nil && $0.type == "expense" })
            file.transactions[other].splitGroupID = file.transactions[refund].splitGroupID
        case .onATransfer:
            let transfer = try #require(file.transactions.firstIndex { $0.type == TransactionType.transfer.rawValue })
            let copy = UUID()
            var twin = file.transactions[transfer]
            twin.id = UUID()
            file.transactions[transfer].splitGroupID = copy
            twin.splitGroupID = copy
            file.transactions.append(twin)
        }
        #expect(throws: BackupError.inconsistentLink(entity: "transactions", field: "splitGroupID")) {
            try BackupValidator.validate(file)
        }
    }

    @Test func exportDropsTheGroupOfALonePart() async throws {
        let (backup, group) = try await splitBackup()
        var file = backup
        let lone = try #require(file.transactions.lastIndex { $0.splitGroupID == group })
        file.transactions.remove(at: lone)
        #expect(file.droppingDanglingLinks() == 1)
        #expect(file.transactions.allSatisfy { $0.splitGroupID == nil })
        try BackupValidator.validate(file)
    }

    /// A backup with a two-part split and a second account; with others, also a refunded purchase and a transfer.
    private func splitBackup(withOthers: Bool = true) async throws -> (BackupDTO, UUID) {
        let fixture = try await makeFixture()
        let savings = try await fixture.ledger.createAccount(
            AccountDraft(name: "Savings", kind: .savings, startingBalance: cad(0), startingBalanceDate: entered),
            now: entered)
        let original = try await spend(10_000, in: fixture)
        try await split(original, [6_000, 4_000], in: fixture)
        if withOthers {
            let refunded = try await spend(2_000, in: fixture)
            try await fixture.ledger.refundTransaction(
                refunded, amount: cad(500), occurredAt: now, notes: nil, calendar: calendar, now: now)
            try await fixture.ledger.create(
                TransactionDraft(
                    amount: cad(1_000), type: .transfer, occurredAt: Self.date(2026, 9, 11),
                    transferAccountID: savings),
                now: entered)
        }
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        try BackupValidator.validate(backup)
        return (backup, try #require(try fixture.record(original).splitGroupID))
    }

    // MARK: Helpers

    private func occurrenceOfASeries(amount: Int64 = 12_000, in fixture: Fixture) async throws -> UUID {
        let series = try await fixture.ledger.createSeries(
            templateAmount: cad(amount), type: .expense, rule: .monthlyOnDay(day: 1),
            timeZone: calendar.timeZone, startDate: now.addingTimeInterval(-40 * 86_400), notes: "Rent", now: entered)
        let seriesID = series
        let stored = try #require(
            try ModelContext(fixture.container).fetch(
                FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == seriesID })
            ).first)
        let due = try #require(stored.nextOccurrence)
        return try await fixture.ledger.materialize(seriesID: series, occurrence: due, now: entered)
    }
}
