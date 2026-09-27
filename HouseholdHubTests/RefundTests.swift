import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 20: a refund is money coming back on the day it comes back, linked to its purchase. Both records stay, and
/// every past figure stays what it was.
struct RefundTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    private let calendar = RefundTests.calendar
    /// Sunday 2026-09-27, noon in Vancouver.
    private let now: Date = RefundTests.date(2026, 9, 27)

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let dining: UUID

        func record(_ id: UUID) throws -> TransactionRecord {
            let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }

        func item(_ id: UUID) throws -> WishlistItem {
            let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id })
            return try #require(try ModelContext(container).fetch(descriptor).first)
        }
    }

    private func cad(_ minorUnits: Int64) -> Money { Money(minorUnits: minorUnits, currencyCode: "CAD") }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(100_000), asOf: Self.date(2026, 8, 1), now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let dining = try await categories.create(
            name: "Shopping", icon: "bag", color: .black, kind: .expense, now: now)
        return Fixture(container: container, ledger: ledger, categories: categories, dining: dining)
    }

    private func buy(_ minorUnits: Int64, on date: Date, in fixture: Fixture) async throws -> UUID {
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(minorUnits), type: .expense, occurredAt: date, categoryID: fixture.dining,
                merchantName: "Store"),
            now: now)
    }

    @discardableResult
    private func refund(
        _ purchase: UUID, _ minorUnits: Int64, on date: Date? = nil, status: TransactionStatus = .posted,
        in fixture: Fixture
    ) async throws -> RefundResult {
        try await fixture.ledger.refundTransaction(
            purchase, amount: cad(minorUnits), occurredAt: date ?? now, status: status, notes: nil,
            calendar: calendar, now: now)
    }

    // MARK: Recording

    @Test func aRefundIsItsOwnRecordLinkedToThePurchaseAndBothStay() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        let result = try await refund(purchase, 12_000, in: fixture)

        let refund = try fixture.record(result.refundID)
        let original = try fixture.record(purchase)
        #expect(refund.type == .refund)
        #expect(refund.refundOfTransactionID == purchase)
        #expect(refund.categoryID == fixture.dining)
        #expect(refund.accountID == original.accountID)
        #expect(refund.merchantID == original.merchantID)
        #expect(refund.occurredAt == now)
        #expect(original.type == .expense && original.status == .posted && original.amountMinorUnits == 12_000)
        #expect(result.wishlistItemToResolve == nil)
        let summary = try await fixture.ledger.refundSummary(for: purchase)
        #expect(summary.isFullyRefunded)
    }

    @Test func theBalanceGetsTheMoneyBack() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        let before = try await fixture.ledger.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        try await refund(purchase, 4_000, in: fixture)
        let after = try await fixture.ledger.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(before.current == cad(88_000))
        #expect(after.current == cad(92_000))
    }

    @Test(arguments: [(4_000 as Int64, 8_000 as Int64), (12_000, 0), (1, 11_999)])
    func partialRefundsAddUpToThePriceAndNoFurther(first: Int64, left: Int64) async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        try await refund(purchase, first, in: fixture)
        let summary = try await fixture.ledger.refundSummary(for: purchase)
        #expect(summary.refunded == cad(first))
        #expect(summary.remaining == cad(left))
        await #expect(throws: LedgerError.refundExceedsRemaining(remaining: cad(left))) {
            try await refund(purchase, left + 1, in: fixture)
        }
        if left > 0 {
            try await refund(purchase, left, in: fixture)
            #expect(try await fixture.ledger.refundSummary(for: purchase).isFullyRefunded)
        }
    }

    @Test func aCancelledRefundFreesItsAmountAndCannotComeBackPastTheLimit() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(10_000, on: Self.date(2026, 9, 10), in: fixture)
        let first = try await refund(purchase, 6_000, in: fixture).refundID
        try await fixture.ledger.setStatus(.cancelled, forTransaction: first, now: now)
        #expect(try await fixture.ledger.refundSummary(for: purchase).remaining == cad(10_000))
        try await refund(purchase, 5_000, in: fixture)
        await #expect(throws: LedgerError.refundExceedsRemaining(remaining: cad(5_000))) {
            try await fixture.ledger.setStatus(.posted, forTransaction: first, now: now)
        }
    }

    @Test func refusedRefundsChangeNothing() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(10_000, on: Self.date(2026, 9, 10), in: fixture)
        let income = try await fixture.ledger.create(
            TransactionDraft(amount: cad(50_000), type: .income, occurredAt: now), now: now)
        await #expect(throws: LedgerError.notRefundable) { try await refund(income, 100, in: fixture) }
        await #expect(throws: LedgerError.refundBeforePurchase) {
            try await refund(purchase, 100, on: Self.date(2026, 9, 9), in: fixture)
        }
        await #expect(throws: LedgerError.refundMustBeLive) {
            try await refund(purchase, 100, status: .cancelled, in: fixture)
        }
        await #expect(throws: LedgerError.nonPositiveAmount) { try await refund(purchase, 0, in: fixture) }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await fixture.ledger.refundTransaction(
                purchase, amount: Money(minorUnits: 100, currencyCode: "USD"), occurredAt: now, notes: nil,
                calendar: calendar, now: now)
        }
        // Same day as the purchase is fine, whatever the time.
        try await refund(purchase, 100, on: Self.date(2026, 9, 10, hour: 1), in: fixture)
        let count = try ModelContext(fixture.container).fetchCount(FetchDescriptor<TransactionRecord>())
        #expect(count == 3)

        try await fixture.ledger.setStatus(.cancelled, forTransaction: income, now: now)
        let cancelled = try await buy(500, on: now, in: fixture)
        try await fixture.ledger.setStatus(.cancelled, forTransaction: cancelled, now: now)
        await #expect(throws: LedgerError.notRefundable) { try await refund(cancelled, 100, in: fixture) }
    }

    @Test func refundsAreNeverMadeFromDraftsOrSeries() async throws {
        let fixture = try await makeFixture()
        await #expect(throws: LedgerError.refundNeedsPurchase) {
            let draft = TransactionDraft(amount: cad(100), type: .refund, occurredAt: now)
            try await fixture.ledger.create(draft, now: now)
        }
        let rule = RecurrenceRule.monthlyOnDay(day: 1)
        await #expect(throws: LedgerError.refundNeedsPurchase) {
            try await fixture.ledger.createSeries(
                templateAmount: cad(100), type: .refund, rule: rule, timeZone: calendar.timeZone, startDate: now,
                now: now)
        }
    }

    // MARK: Protecting history

    @Test func aPurchaseWithRefundsKeepsWhatTheyDependOn() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(10_000, on: Self.date(2026, 9, 10), in: fixture)
        try await refund(purchase, 4_000, in: fixture)
        func draft(_ minorUnits: Int64, _ type: TransactionType = .expense, _ status: TransactionStatus = .posted)
            -> TransactionDraft
        {
            TransactionDraft(
                amount: cad(minorUnits), type: type, occurredAt: Self.date(2026, 9, 10), status: status,
                categoryID: type == .expense ? fixture.dining : nil)
        }
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.deleteTransaction(purchase, alsoDisableSeries: false, now: now)
        }
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.setStatus(.cancelled, forTransaction: purchase, now: now)
        }
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.update(purchase, with: draft(3_999), now: now)
        }
        await #expect(throws: LedgerError.purchaseHasRefunds) {
            try await fixture.ledger.update(purchase, with: draft(10_000, .income), now: now)
        }
        // Down to the refunded amount, a new note or a pending status is fine.
        try await fixture.ledger.update(purchase, with: draft(4_000, .expense, .pending), now: now)
        #expect(try fixture.record(purchase).amountMinorUnits == 4_000)
    }

    @Test func aRefundIsEditedAndDeletedOnItsOwn() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(10_000, on: Self.date(2026, 9, 10), in: fixture)
        let id = try await refund(purchase, 4_000, in: fixture).refundID
        await #expect(throws: LedgerError.refundNeedsPurchase) {
            try await fixture.ledger.update(
                id, with: TransactionDraft(amount: cad(4_000), type: .expense, occurredAt: now), now: now)
        }
        try await fixture.ledger.updateRefund(
            id, amount: cad(10_000), occurredAt: now, status: .pending, notes: " returned ", calendar: calendar,
            now: now)
        let edited = try fixture.record(id)
        #expect(edited.amountMinorUnits == 10_000 && edited.status == .pending && edited.notes == "returned")
        await #expect(throws: LedgerError.refundExceedsRemaining(remaining: cad(10_000))) {
            try await fixture.ledger.updateRefund(
                id, amount: cad(10_001), occurredAt: now, status: .posted, notes: nil, calendar: calendar, now: now)
        }
        try await fixture.ledger.deleteTransaction(id, alsoDisableSeries: false, now: now)
        #expect(try await fixture.ledger.refundSummary(for: purchase).refunded == cad(0))
        // With its refunds gone, the purchase can go too.
        try await fixture.ledger.deleteTransaction(purchase, alsoDisableSeries: false, now: now)
    }

    // MARK: Spending

    @Test func aRefundLowersItsCategorysSpendingInItsOwnMonthOnly() async throws {
        let fixture = try await makeFixture()
        // Set in August, so August has a budget month too.
        try await fixture.categories.setBudget(
            for: fixture.dining, limit: cad(50_000), rollsOver: false, now: Self.date(2026, 8, 1), calendar: calendar)
        let august = try await buy(20_000, on: Self.date(2026, 8, 20), in: fixture)
        let september = try await buy(12_000, on: Self.date(2026, 9, 5), in: fixture)
        try await refund(september, 2_000, on: Self.date(2026, 9, 6), in: fixture)
        // An August purchase returned in September: August keeps what was spent.
        try await refund(august, 20_000, on: Self.date(2026, 9, 7), in: fixture)

        func spent(_ month: Date) async throws -> Money? {
            try await fixture.ledger.budgetReport(month: month, calendar: calendar)
                .first { $0.categoryID == fixture.dining }?.spent
        }
        #expect(try await spent(Self.date(2026, 8, 15)) == cad(20_000))
        // September: 120.00 spent, 20.00 + 200.00 back: never below zero.
        #expect(try await spent(Self.date(2026, 9, 15)) == cad(0))
    }

    @Test func analyticsCountsRefundsAsLessSpendingNotAsIncome() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.ledger.create(
            TransactionDraft(amount: cad(300_000), type: .income, occurredAt: Self.date(2026, 9, 1)), now: now)
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 5), in: fixture)
        try await refund(purchase, 2_000, on: Self.date(2026, 9, 6), in: fixture)

        let report = try await AnalyticsService.make(container: fixture.container)
            .report(period: .thisMonth, now: now, calendar: calendar)
        #expect(report.income == cad(300_000))
        #expect(report.refunds == cad(2_000))
        #expect(report.expense == cad(10_000))
        #expect(report.net == cad(290_000))
        #expect(report.byCategory.first { $0.categoryID == fixture.dining }?.total == cad(10_000))
        #expect(report.topMerchants.first?.total == cad(10_000))

        let summary = try await fixture.ledger.dashboardSummary(now: now, calendar: calendar)
        // The week of Sep 27 has neither; the purchase and refund both fall earlier.
        #expect(summary.spentThisWeek == cad(0))
    }

    @Test func engineShowsZeroNotNegativeSpendingForALaterMonthReturn() throws {
        let category = UUID()
        func entry(_ minorUnits: Int64, _ type: TransactionType, _ date: Date) -> AnalyticsEntry {
            AnalyticsEntry(
                amount: cad(minorUnits), type: type, status: .posted, occurredAt: date, categoryID: category,
                merchantID: nil, merchantName: nil)
        }
        let report = try AnalyticsEngine().report(
            [entry(5_000, .refund, Self.date(2026, 9, 3)), entry(1_000, .expense, Self.date(2026, 9, 4))],
            period: .thisMonth, now: now, calendar: calendar, currencyCode: "CAD")
        #expect(report.expense == cad(0))
        #expect(report.refunds == cad(5_000))
        #expect(report.net == cad(4_000))
        #expect(report.byCategory.isEmpty)
        #expect(report.trend.allSatisfy { $0.expense.minorUnits >= 0 })
    }

    // MARK: Wishlist

    private func boughtItem(_ fixture: Fixture) async throws -> (item: UUID, purchase: UUID) {
        let item = try await fixture.ledger.createWishlistItem(
            WishlistDraft(name: "Bike", estimatedPrice: cad(25_000)), now: now)
        let purchase = try await fixture.ledger.purchaseWishlistItem(
            item, actualPrice: cad(24_000), occurredAt: Self.date(2026, 9, 10), categoryID: fixture.dining, now: now)
        return (item, purchase)
    }

    @Test func aPartialRefundLeavesAWishlistItemPurchased() async throws {
        let fixture = try await makeFixture()
        let (item, purchase) = try await boughtItem(fixture)
        let result = try await refund(purchase, 4_000, in: fixture)
        #expect(result.wishlistItemToResolve == nil)
        #expect(try fixture.item(item).status == .purchased)
        await #expect(throws: LedgerError.notRefundable) {
            try await fixture.ledger.resolveRefundedWishlistItem(item, choice: .keepOnWishlist, now: now)
        }
    }

    @Test func keepingARefundedItemPutsItBackOnTheWishlistAndItCanBeBoughtAgain() async throws {
        let fixture = try await makeFixture()
        let (item, purchase) = try await boughtItem(fixture)
        let result = try await refund(purchase, 24_000, in: fixture)
        #expect(result.wishlistItemToResolve == item)
        try await fixture.ledger.resolveRefundedWishlistItem(item, choice: .keepOnWishlist, now: now)

        let kept = try fixture.item(item)
        #expect(kept.status == .wanted && kept.purchasedTransactionID == nil && kept.actualPriceMinorUnits == nil)
        let old = try fixture.record(purchase)
        #expect(old.wishlistItemID == nil && old.status == .posted && old.amountMinorUnits == 24_000)
        let again = try await fixture.ledger.purchaseWishlistItem(
            item, actualPrice: cad(23_000), occurredAt: now, categoryID: fixture.dining, now: now)
        #expect(try fixture.item(item).purchasedTransactionID == again)
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        try BackupValidator.validate(backup)
    }

    @Test func removingARefundedItemArchivesItWithItsHistory() async throws {
        let fixture = try await makeFixture()
        let (item, purchase) = try await boughtItem(fixture)
        try await refund(purchase, 24_000, in: fixture)
        try await fixture.ledger.resolveRefundedWishlistItem(item, choice: .removeFromWishlist, now: now)
        let removed = try fixture.item(item)
        #expect(removed.status == .archived && removed.purchasedTransactionID == purchase)
        #expect(try fixture.record(purchase).wishlistItemID == item)
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        try BackupValidator.validate(backup)
    }

    // MARK: Backup

    @Test func refundsRoundTripThroughABackup() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        try await refund(purchase, 4_000, in: fixture)
        let backup = BackupService.make(container: fixture.container)
        let exported = try await backup.snapshot(now: now, appVersion: "1.1") { _ in nil }
        #expect(exported.schemaVersion == 3)
        #expect(exported.transactions.contains { $0.refundOfTransactionID == purchase && $0.type == "refund" })
        let json = try BackupDTO.encoder().encode(exported)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: json)
        try BackupValidator.validate(decoded)

        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(decoded, availableMedia: [], now: now)
        let again = try await BackupService.make(container: target).snapshot(now: now, appVersion: "1.1") { _ in nil }
        #expect(again == decoded)
        let restored = TransactionService.make(container: target)
        #expect(try await restored.refundSummary(for: purchase).refunded == cad(4_000))
    }

    @Test func aBackupWithAnImpossibleRefundIsRefused() async throws {
        let fixture = try await makeFixture()
        let purchase = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        try await refund(purchase, 4_000, in: fixture)
        let good = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        let refundIndex = try #require(good.transactions.firstIndex { $0.type == "refund" })

        var tooMuch = good
        tooMuch.transactions[refundIndex].amountMinorUnits = 12_001
        #expect(throws: BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID")) {
            try BackupValidator.validate(tooMuch)
        }
        var orphan = good
        orphan.transactions[refundIndex].refundOfTransactionID = UUID()
        #expect(throws: BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID")) {
            try BackupValidator.validate(orphan)
        }
        var linkedExpense = good
        let purchaseIndex = try #require(good.transactions.firstIndex { $0.id == purchase })
        linkedExpense.transactions[purchaseIndex].refundOfTransactionID = purchase
        #expect(throws: BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID")) {
            try BackupValidator.validate(linkedExpense)
        }
    }

    @Test func aVersion2BackupStillRestores() async throws {
        let fixture = try await makeFixture()
        _ = try await buy(12_000, on: Self.date(2026, 9, 10), in: fixture)
        var older = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        older.schemaVersion = 2
        try BackupValidator.validate(older)
        #expect(older.upgradedToCurrent().schemaVersion == BackupDTO.currentSchemaVersion)
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let summary = try await BackupService.make(container: target).restore(older, availableMedia: [], now: now)
        #expect(summary.transactions == 1)
    }
}
