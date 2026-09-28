import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 22: a recurring item is a bill or a purchase. A purchase is an expense at a store; its occurrences post with
/// that store as the merchant, it gets no "due" reminder, and it projects exactly like a bill.
struct RecurringPurchaseTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func makeLedger() async throws -> (ModelContainer, TransactionService) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(100_000), asOf: now.addingTimeInterval(-90 * 86_400), now: now)
        return (container, ledger)
    }

    private func series(_ container: ModelContainer, _ id: UUID) throws -> RecurringTransaction {
        let all = try ModelContext(container).fetch(FetchDescriptor<RecurringTransaction>())
        return try #require(all.first { $0.id == id })
    }

    private func merchantName(_ container: ModelContainer, _ id: UUID?) throws -> String? {
        guard let id else { return nil }
        return try ModelContext(container).fetch(FetchDescriptor<Merchant>()).first { $0.id == id }?.displayName
    }

    /// Weekly groceries, starting tomorrow so every occurrence is still upcoming.
    @discardableResult
    private func groceries(
        _ ledger: TransactionService, store: String? = "  Costco  ", start: Date? = nil
    ) async throws -> UUID {
        try await ledger.createSeries(
            templateAmount: cad(18_000), type: .expense, rule: .weekly(interval: 1, weekday: 7), timeZone: zone,
            startDate: start ?? now.addingTimeInterval(86_400), notes: "Groceries", kind: .purchase,
            merchantName: store, now: now)
    }

    // MARK: Service

    @Test func aPurchaseKeepsItsKindAndItsStore() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger)
        let stored = try series(container, id)
        #expect(stored.kind == .purchase)
        #expect(stored.kindRawValue == RecurringKind.purchase.rawValue)
        #expect(try merchantName(container, stored.merchantID) == "Costco", "The store name is trimmed")
        let snapshot = try stored.series()
        #expect(snapshot.kind == .purchase)
        #expect(snapshot.merchantID == stored.merchantID)

        // A second purchase at the same store reuses its merchant.
        let again = try await groceries(ledger, store: "costco")
        #expect(try series(container, again).merchantID == stored.merchantID)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Merchant>()) == 1)
    }

    @Test func aBillIsStoredAsBeforeUnlessItNamesAStore() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            notes: "Rent", now: now)
        let stored = try series(container, id)
        #expect(stored.kind == .bill)
        #expect(stored.kindRawValue == nil, "A bill is stored as nil, like every series written before SchemaV3")
        #expect(stored.merchantID == nil)
    }

    @Test(arguments: [TransactionType.income, .transfer, .refund])
    func aPurchaseMustBeAnExpense(type: TransactionType) async throws {
        let (container, ledger) = try await makeLedger()
        await #expect(throws: LedgerError.purchaseMustBeExpense) {
            try await ledger.createSeries(
                templateAmount: cad(5_000), type: type, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
                kind: .purchase, merchantName: "Store", now: now)
        }
        let id = try await groceries(ledger)
        await #expect(throws: LedgerError.purchaseMustBeExpense) {
            try await ledger.updateSeries(
                id, templateAmount: cad(5_000), type: type, rule: .monthlyOnDay(day: 1), startDate: now,
                categoryID: nil, notes: nil, kind: .purchase, merchantName: "Store", now: now)
        }
        #expect(try series(container, id).type == .expense, "A refused edit changes nothing")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<RecurringTransaction>()) == 1)
    }

    @Test func aRecurringTransferNamesNoStore() async throws {
        let (_, ledger) = try await makeLedger()
        await #expect(throws: LedgerError.transferHasNoCategory) {
            try await ledger.createSeries(
                templateAmount: cad(5_000), type: .transfer, rule: .monthlyOnDay(day: 1), timeZone: zone,
                startDate: now, transferAccountID: UUID(), merchantName: "Store", now: now)
        }
    }

    @Test func editingChangesTheStoreAndTheKind() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger)
        let start = now.addingTimeInterval(86_400)
        try await ledger.updateSeries(
            id, templateAmount: cad(20_000), type: .expense, rule: .weekly(interval: 1, weekday: 7), startDate: start,
            categoryID: nil, notes: "Groceries", kind: .purchase, merchantName: "Save-On-Foods", now: now)
        #expect(try merchantName(container, try series(container, id).merchantID) == "Save-On-Foods")

        try await ledger.updateSeries(
            id, templateAmount: cad(20_000), type: .expense, rule: .weekly(interval: 1, weekday: 7), startDate: start,
            categoryID: nil, notes: "Groceries", kind: .bill, merchantName: nil, now: now)
        let bill = try series(container, id)
        #expect(bill.kind == .bill)
        #expect(bill.kindRawValue == nil)
        #expect(bill.merchantID == nil)
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func editingWithoutAStoreClearsIt(store: String?) async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger)
        try await ledger.updateSeries(
            id, templateAmount: cad(18_000), type: .expense, rule: .weekly(interval: 1, weekday: 7),
            startDate: now.addingTimeInterval(86_400), categoryID: nil, notes: "Groceries", kind: .purchase,
            merchantName: store, now: now)
        let stored = try series(container, id)
        #expect(stored.kind == .purchase)
        #expect(stored.merchantID == nil)
    }

    @Test func postingAPurchaseRecordsItsStore() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger, start: now.addingTimeInterval(-30 * 86_400))
        let stored = try series(container, id)
        let occurrence = try #require(stored.nextOccurrence)
        let recordID = try await ledger.materialize(seriesID: id, occurrence: occurrence, now: now)
        let record = try #require(
            try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>()).first { $0.id == recordID })
        #expect(record.type == .expense)
        #expect(record.source == .recurring)
        #expect(record.merchantID == stored.merchantID)
        #expect(record.merchantNameSnapshot == "Costco")

        // A bill without a store posts without a merchant, as before.
        let rent = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone,
            startDate: now.addingTimeInterval(-40 * 86_400), notes: "Rent", now: now)
        let due = try #require(try series(container, rent).nextOccurrence)
        let paid = try await ledger.materialize(seriesID: rent, occurrence: due, now: now)
        let paidRecord = try #require(
            try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>()).first { $0.id == paid })
        #expect(paidRecord.merchantID == nil)
        #expect(paidRecord.merchantNameSnapshot == nil)
    }

    @Test func upcomingCarriesTheKindAndTheStore() async throws {
        let (_, ledger) = try await makeLedger()
        try await groceries(ledger)
        try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .daily(interval: 1), timeZone: zone,
            startDate: now.addingTimeInterval(86_400), notes: "Rent", now: now)
        let upcoming = try await ledger.upcomingOccurrences(now: now, calendar: calendar, days: 7)
        let purchases = upcoming.filter { $0.kind == .purchase }
        let bills = upcoming.filter { $0.kind == .bill }
        #expect(!purchases.isEmpty)
        #expect(!bills.isEmpty)
        #expect(purchases.allSatisfy { $0.merchantName == "Costco" && $0.title == "Groceries" })
        #expect(bills.allSatisfy { $0.merchantName == nil && $0.title == "Rent" })
    }

    @Test func remindersAreForBillsOnly() async throws {
        let (_, ledger) = try await makeLedger()
        try await groceries(ledger)
        try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .daily(interval: 1), timeZone: zone,
            startDate: now.addingTimeInterval(86_400), notes: "Rent", now: now)
        let upcoming = try await ledger.upcomingOccurrences(now: now, calendar: calendar, days: 7)
        let wording = ReminderWording(
            taskTitle: "Task due today", taskBody: { $0 }, billTitle: "Bill due tomorrow",
            billBody: { name in "\(name ?? "A bill") is due tomorrow." })
        let plan = ReminderPlanner().plan(
            tasks: [], bills: upcoming, settings: ReminderSettings(tasksDue: true, billsDue: true), wording: wording,
            now: now, calendar: calendar)
        let billIDs = Set(upcoming.filter { $0.kind == .bill }.map { "bill-\($0.id)" })
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { billIDs.contains($0.id) }, "No reminder for a purchase")
        #expect(plan.allSatisfy { $0.body == "Rent is due tomorrow." })
    }

    @Test(arguments: RecurringKind.allCases)
    func thePlannerRemindsOfBillsNotPurchases(kind: RecurringKind) {
        let wording = ReminderWording(
            taskTitle: "Task", taskBody: { $0 }, billTitle: "Bill due tomorrow", billBody: { $0 ?? "A bill" })
        let item = UpcomingOccurrence(
            seriesID: UUID(), date: now.addingTimeInterval(3 * 86_400), amount: cad(18_000), type: .expense,
            title: "Groceries", kind: kind, merchantName: "Costco")
        let plan = ReminderPlanner().plan(
            tasks: [], bills: [item], settings: ReminderSettings(tasksDue: false, billsDue: true), wording: wording,
            now: now, calendar: calendar)
        #expect(plan.count == (kind == .bill ? 1 : 0))
    }

    @Test func aPurchaseProjectsLikeABill() async throws {
        var projected: [Money] = []
        for kind in RecurringKind.allCases {
            let (_, ledger) = try await makeLedger()
            try await ledger.createSeries(
                templateAmount: cad(18_000), type: .expense, rule: .weekly(interval: 1, weekday: 7), timeZone: zone,
                startDate: now.addingTimeInterval(86_400), kind: kind,
                merchantName: kind == .purchase ? "Costco" : nil, now: now)
            let balances = try await ledger.balanceSnapshot(
                now: now, calendar: calendar, includePendingInProjection: false)
            projected.append(balances.projected)
        }
        #expect(projected.count == 2)
        #expect(projected.first == projected.last)
        #expect(projected.first != cad(100_000), "The occurrences are projected")
    }

    // MARK: Backup

    private func snapshot(_ container: ModelContainer) async throws -> BackupDTO {
        try await BackupService.make(container: container).snapshot(now: now, appVersion: "1") { _ in nil }
    }

    @Test func aVersion4BackupKeepsEachKind() async throws {
        let (container, ledger) = try await makeLedger()
        let purchase = try await groceries(ledger)
        let rent = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            notes: "Rent", now: now)
        let backup = try await snapshot(container)
        #expect(backup.schemaVersion == BackupDTO.currentSchemaVersion)
        let kinds = Dictionary(uniqueKeysWithValues: backup.recurringTransactions.map { ($0.id, $0.kind) })
        #expect(kinds[purchase] == .some("purchase"))
        #expect(kinds[rent] == .some(nil), "A bill is written without a kind, as it is stored")

        let data = try BackupDTO.encoder().encode(backup)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: data)
        #expect(decoded == backup)
        try BackupValidator.validate(decoded)
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(decoded, availableMedia: [], now: now)
        #expect(try series(target, purchase).kind == .purchase)
        #expect(try series(target, rent).kind == .bill)
        #expect(try merchantName(target, try series(target, purchase).merchantID) == "Costco")
        #expect(try await snapshot(target) == backup, "The round trip is exact")
    }

    @Test func aVersion3BackupReadsEverySeriesAsABill() async throws {
        let (container, ledger) = try await makeLedger()
        let rent = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            notes: "Rent", now: now)
        var older = try await snapshot(container)
        older.schemaVersion = 3
        try BackupValidator.validate(older)
        let data = try BackupDTO.encoder().encode(older)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: data)
        #expect(decoded.recurringTransactions.allSatisfy { $0.kind == nil })
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(decoded, availableMedia: [], now: now)
        let restored = try series(target, rent)
        #expect(restored.kind == .bill)
        #expect(restored.kindRawValue == nil)
    }

    @Test(arguments: [1, 2, 3])
    func anOlderBackupNamingAKindIsRefused(version: Int) async throws {
        let (container, ledger) = try await makeLedger()
        try await groceries(ledger)
        var older = try await snapshot(container)
        older.schemaVersion = version
        if version == 1 {
            older.settings.startingBalanceMinorUnits = 100_000
            older.settings.startingBalanceDate = now.addingTimeInterval(-90 * 86_400)
        }
        #expect(throws: BackupError.invalidValue(entity: "recurringTransactions", field: "kind", value: "purchase")) {
            try BackupValidator.validate(older)
        }
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        await #expect(throws: BackupError.self) {
            try await BackupService.make(container: target).restore(older, availableMedia: [], now: now)
        }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
    }

    @Test func aBackupPurchaseMustBeAnExpenseOfAKnownKind() async throws {
        let (container, ledger) = try await makeLedger()
        try await groceries(ledger)
        let good = try await snapshot(container)
        try BackupValidator.validate(good)
        let index = try #require(good.recurringTransactions.firstIndex { $0.kind == "purchase" })

        var income = good
        income.recurringTransactions[index].type = TransactionType.income.rawValue
        #expect(throws: BackupError.inconsistentLink(entity: "recurringTransactions", field: "kind")) {
            try BackupValidator.validate(income)
        }
        var unknown = good
        unknown.recurringTransactions[index].kind = "subscription"
        let unreadable = BackupError.invalidValue(entity: "recurringTransactions", field: "kind", value: "subscription")
        #expect(throws: unreadable) { try BackupValidator.validate(unknown) }
        var explicitBill = good
        explicitBill.recurringTransactions[index].kind = RecurringKind.bill.rawValue
        try BackupValidator.validate(explicitBill)
    }

    // MARK: Data-safety review (Sprint 22)

    /// S4: a file that names a bill restores it as the service stores one (nil), so it exports exactly the same.
    @Test func aBackupNamingABillRestoresItAsStored() async throws {
        let (container, ledger) = try await makeLedger()
        let rent = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            notes: "Rent", now: now)
        var backup = try await snapshot(container)
        let index = try #require(backup.recurringTransactions.firstIndex { $0.id == rent })
        backup.recurringTransactions[index].kind = RecurringKind.bill.rawValue
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        #expect(try series(target, rent).kindRawValue == nil)
        #expect(try await snapshot(target).recurringTransactions.first { $0.id == rent }?.kind == nil)
    }

    /// S5: saving the same store name keeps the series' own merchant, even when another one shares the name.
    @Test func theSameStoreNameKeepsItsMerchant() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger)
        let original = try #require(try series(container, id).merchantID)
        let context = ModelContext(container)
        context.insert(Merchant(displayName: "Costco", now: now))
        try context.save()
        try await ledger.updateSeries(
            id, templateAmount: cad(19_000), type: .expense, rule: .weekly(interval: 1, weekday: 7),
            startDate: now.addingTimeInterval(86_400), categoryID: nil, notes: "Groceries", kind: .purchase,
            merchantName: "costco ", now: now)
        #expect(try series(container, id).merchantID == original)
    }

    /// S3: an impossible rule is refused before anything is looked up or changed, so no new store is left behind.
    @Test func aRefusedEditLeavesNoNewStore() async throws {
        let (container, ledger) = try await makeLedger()
        let id = try await groceries(ledger)
        await #expect(throws: RecurrenceRuleError.self) {
            try await ledger.updateSeries(
                id, templateAmount: cad(19_000), type: .expense, rule: .monthlyOnDay(day: 40), startDate: now,
                categoryID: nil, notes: "Groceries", kind: .purchase, merchantName: "New Store", now: now)
        }
        try await ledger.createSeries(
            templateAmount: cad(5_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            notes: "Phone", now: now)
        let names = try ModelContext(container).fetch(FetchDescriptor<Merchant>()).map(\.displayName)
        #expect(names == ["Costco"])
        #expect(try series(container, id).templateAmount == cad(18_000))
    }

    /// S6: posting an occurrence moves the current balance the same way for either kind.
    @Test func postingEitherKindMovesTheBalanceAlike() async throws {
        let (container, ledger) = try await makeLedger()
        let start = now.addingTimeInterval(-8 * 86_400)
        let purchase = try await groceries(ledger, start: start)
        let bill = try await ledger.createSeries(
            templateAmount: cad(18_000), type: .expense, rule: .weekly(interval: 1, weekday: 7), timeZone: zone,
            startDate: start, notes: "Cleaner", now: now)
        func current() async throws -> Money {
            try await ledger.dashboardSummary(now: now, calendar: calendar).balance.current
        }
        let before = try await current()
        let purchaseDate = try #require(try series(container, purchase).nextOccurrence)
        try await ledger.materialize(seriesID: purchase, occurrence: purchaseDate, now: now)
        let afterPurchase = try await current()
        let billDate = try #require(try series(container, bill).nextOccurrence)
        try await ledger.materialize(seriesID: bill, occurrence: billDate, now: now)
        let afterBill = try await current()
        #expect(purchaseDate <= now)
        #expect(before.minorUnits - afterPurchase.minorUnits == 18_000)
        #expect(afterPurchase.minorUnits - afterBill.minorUnits == 18_000)
    }
}
