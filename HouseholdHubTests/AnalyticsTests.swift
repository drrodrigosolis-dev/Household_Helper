import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct AnalyticsTests {
    private typealias Entry = AnalyticsEntry

    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!, firstWeekday: 2)

    /// 2026-09-26 12:00 in Vancouver.
    private var now: Date { date(2026, 9, 26, hour: 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var parts = DateComponents(year: year, month: month, day: day, hour: hour)
        parts.timeZone = calendar.timeZone
        return calendar.calendar.date(from: parts)!
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func expense(_ units: Int64, on day: Date, category: UUID? = nil, merchant: String? = nil) -> Entry {
        AnalyticsEntry(
            amount: cad(units), type: .expense, status: .posted, occurredAt: day, categoryID: category,
            merchantName: merchant)
    }

    private func report(_ entries: [AnalyticsEntry], _ period: AnalyticsPeriod = .thisMonth) throws -> AnalyticsReport {
        try AnalyticsEngine().report(entries, period: period, now: now, calendar: calendar, currencyCode: "CAD")
    }

    // MARK: Periods

    static let periodCases: [(AnalyticsPeriod, Int, Int, Int, Int)] = [
        (.thisMonth, 2026, 9, 2026, 10),
        (.lastMonth, 2026, 8, 2026, 9),
        (.last3Months, 2026, 7, 2026, 10),
        (.thisYear, 2026, 1, 2026, 10),
        (.last12Months, 2025, 10, 2026, 10),
    ]

    @Test(arguments: periodCases)
    func periodsCoverWholeMonths(period: AnalyticsPeriod, fromYear: Int, fromMonth: Int, toYear: Int, toMonth: Int) {
        let interval = period.interval(now: now, calendar: calendar)
        #expect(interval.start == date(fromYear, fromMonth, 1, hour: 0))
        #expect(interval.end == date(toYear, toMonth, 1, hour: 0))
    }

    // MARK: Totals

    @Test func onlyPostedIncomeAndExpenseInThePeriodCount() throws {
        let inPeriod = date(2026, 9, 10)
        let entries = [
            expense(1_000, on: inPeriod),
            AnalyticsEntry(amount: cad(5_000), type: .income, status: .posted, occurredAt: inPeriod),
            AnalyticsEntry(amount: cad(700), type: .expense, status: .pending, occurredAt: inPeriod),
            AnalyticsEntry(amount: cad(800), type: .expense, status: .cancelled, occurredAt: inPeriod),
            AnalyticsEntry(amount: cad(900), type: .transfer, status: .posted, occurredAt: inPeriod),
            expense(2_000, on: date(2026, 8, 31, hour: 23)),
            expense(3_000, on: date(2026, 10, 1, hour: 0)),
        ]
        let result = try report(entries)
        #expect(result.income == cad(5_000))
        #expect(result.expense == cad(1_000))
        #expect(result.net == cad(4_000))
    }

    @Test func netIsNegativeWhenSpendingExceedsIncome() throws {
        let day = date(2026, 9, 2)
        let entries = [
            expense(9_000, on: day),
            AnalyticsEntry(amount: cad(4_000), type: .income, status: .posted, occurredAt: day),
        ]
        #expect(try report(entries).net == cad(-5_000))
    }

    @Test func foreignCurrencyIsRefusedNotMixed() {
        let usd = AnalyticsEntry(
            amount: Money(minorUnits: 100, currencyCode: "USD"), type: .expense, status: .posted,
            occurredAt: date(2026, 9, 3))
        #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) { try report([usd]) }
    }

    // MARK: Breakdowns

    @Test func categoriesAreLargestFirstWithSharesAndAnUncategorizedBucket() throws {
        let food = UUID()
        let home = UUID()
        let day = date(2026, 9, 12)
        let entries = [
            expense(3_000, on: day, category: food), expense(1_000, on: day, category: food),
            expense(5_000, on: day, category: home), expense(1_000, on: day),
        ]
        let categories = try report(entries).byCategory
        #expect(categories.map(\.categoryID) == [home, food, nil])
        #expect(categories.map(\.total) == [cad(5_000), cad(4_000), cad(1_000)])
        #expect(categories.map(\.share) == [0.5, 0.4, 0.1])
    }

    @Test func monthTrendHasEveryWeekIncludingEmptyOnes() throws {
        let entries = [expense(1_000, on: date(2026, 9, 2)), expense(2_000, on: date(2026, 9, 23))]
        let trend = try report(entries).trend
        // September 2026 in Monday-first weeks: Aug 31, Sep 7, 14, 21, 28.
        let weeks = [date(2026, 8, 31, hour: 0)] + [7, 14, 21, 28].map { date(2026, 9, $0, hour: 0) }
        #expect(trend.map(\.start) == weeks)
        #expect(trend.map(\.expense) == [cad(1_000), cad(0), cad(0), cad(2_000), cad(0)])
        let noIncome = trend.allSatisfy { $0.income == cad(0) }
        #expect(noIncome)
    }

    @Test func yearTrendIsMonthly() throws {
        let entries = [
            AnalyticsEntry(amount: cad(5_000), type: .income, status: .posted, occurredAt: date(2026, 2, 15)),
            expense(1_500, on: date(2026, 9, 1)),
        ]
        let trend = try report(entries, .thisYear).trend
        #expect(trend.count == 9)
        #expect(trend[1].income == cad(5_000))
        #expect(trend[8].expense == cad(1_500))
    }

    @Test func topMerchantsGroupByMerchantAndKeepTheLatestName() throws {
        let entries = [
            expense(1_000, on: date(2026, 9, 3), merchant: "cafe luna"),
            expense(2_000, on: date(2026, 9, 9), merchant: "Café Luna"),
            expense(500, on: date(2026, 9, 4), merchant: "Bakery"),
            expense(9_000, on: date(2026, 9, 5)),
        ]
        let merchants = try report(entries).topMerchants
        #expect(merchants.map(\.name) == ["Café Luna", "Bakery"])
        #expect(merchants.map(\.total) == [cad(3_000), cad(500)])
        #expect(merchants.map(\.count) == [2, 1])
    }

    // MARK: Ledger agreement

    @Test func futureDatedPostedItemsAreNotCountedYet() throws {
        // Posted but dated tomorrow: the balance treats it as projected, so analytics must not count it either.
        let entries = [expense(1_000, on: date(2026, 9, 20)), expense(8_000, on: date(2026, 9, 27))]
        let result = try report(entries)
        #expect(result.expense == cad(1_000))
        let trendTotal = try Money.sum(result.trend.map(\.expense), currencyCode: "CAD")
        #expect(trendTotal == cad(1_000))
    }

    @Test(arguments: AnalyticsPeriod.allCases)
    func trendAddsUpToTheTotals(period: AnalyticsPeriod) throws {
        var entries: [Entry] = []
        for index in 0..<400 {
            let day = now.addingTimeInterval(-Double(index) * 86_400)
            entries.append(expense(Int64(100 + index), on: day))
            entries.append(Entry(amount: cad(Int64(50 + index)), type: .income, status: .posted, occurredAt: day))
        }
        let result = try report(entries, period)
        #expect(try Money.sum(result.trend.map(\.expense), currencyCode: "CAD") == result.expense)
        #expect(try Money.sum(result.trend.map(\.income), currencyCode: "CAD") == result.income)
    }

    @Test func weeklyBucketsSurviveDSTStartingAtMidnight() throws {
        // America/Santiago moves 2026-09-06 00:00 → 01:00; with Sunday-first weeks that week starts at 01:00.
        let santiago = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Santiago")!, firstWeekday: 1)
        var parts = DateComponents(year: 2026, month: 9, day: 26, hour: 12)
        parts.timeZone = santiago.timeZone
        let today = try #require(santiago.calendar.date(from: parts))
        let entries = (0..<25).map { offset in
            expense(1_000, on: today.addingTimeInterval(-Double(offset) * 86_400))
        }
        let result = try AnalyticsEngine().report(
            entries, period: .thisMonth, now: today, calendar: santiago, currencyCode: "CAD")
        #expect(try Money.sum(result.trend.map(\.expense), currencyCode: "CAD") == result.expense)
        #expect(result.expense == cad(25_000))
    }

    @Test func thisWeekMatchesTheDashboard() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let analytics = AnalyticsService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        for (units, day) in [(1_250, 21), (3_000, 24), (999, 26), (4_000, 18), (7_000, 27)] as [(Int64, Int)] {
            let draft = TransactionDraft(amount: cad(units), type: .expense, occurredAt: date(2026, 9, day, hour: 9))
            try await ledger.create(draft, now: now)
        }
        let dashboard = try await ledger.dashboardSummary(now: now, calendar: calendar)
        let result = try await analytics.report(period: .thisMonth, now: now, calendar: calendar)
        let week = try #require(result.trend.first { $0.start == calendar.startOfWeek(for: now) })
        #expect(week.expense == dashboard.spentThisWeek)
        #expect(week.expense == cad(5_249))
    }

    @Test func unreadableStoredStatusFailsTheReadInsteadOfHidingTheRecord() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let id = try await ledger.create(
            TransactionDraft(amount: cad(500), type: .expense, occurredAt: date(2026, 9, 10)), now: now)
        let context = ModelContext(container)
        let record = try #require(
            try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first)
        record.statusRawValue = "archived-by-a-future-version"
        try context.save()
        let analytics = AnalyticsService.make(container: container)
        await #expect(throws: LedgerError.unreadableRecord(field: "status", value: "archived-by-a-future-version")) {
            try await analytics.report(period: .thisMonth, now: now, calendar: calendar)
        }
    }

    @Test func merchantNameIsTheLatestNonEmptyOne() throws {
        let merchantID = UUID()
        let entries = [
            Entry(
                amount: cad(1_000), type: .expense, status: .posted, occurredAt: date(2026, 9, 3),
                merchantID: merchantID, merchantName: "Corner Shop"),
            Entry(
                amount: cad(2_000), type: .expense, status: .posted, occurredAt: date(2026, 9, 9),
                merchantID: merchantID, merchantName: nil),
        ]
        let merchants = try report(entries).topMerchants
        #expect(merchants.map(\.name) == ["Corner Shop"])
        #expect(merchants.map(\.total) == [cad(3_000)])
    }

    // MARK: Service

    @Test func serviceReportsFromTheStoreAndRemembersThePeriod() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let analytics = AnalyticsService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let posted = TransactionDraft(amount: cad(4_750), type: .expense, occurredAt: date(2026, 9, 20))
        try await ledger.create(posted, now: now)
        let pending = TransactionDraft(
            amount: cad(100), type: .expense, occurredAt: date(2026, 9, 21), status: .pending)
        try await ledger.create(pending, now: now)
        let result = try await analytics.report(period: .thisMonth, now: now, calendar: calendar)
        #expect(result.expense == cad(4_750))

        try await ledger.setDefaultAnalyticsPeriod(.last3Months, now: now)
        let settings = try ModelContext(container).fetch(FetchDescriptor<AppSettings>())
        #expect(settings.first?.defaultAnalyticsPeriod == .last3Months)
    }

    /// NFR: recompute under 1 s for 5 years of history. About 18,000 transactions (10 a day) in the pure engine.
    @Test func fiveYearsOfHistoryComputesWellUnderASecond() throws {
        var entries: [AnalyticsEntry] = []
        let categories = (0..<12).map { _ in UUID() }
        for index in 0..<18_250 {
            let day = now.addingTimeInterval(-Double(index) * 8_640)
            let amount = Int64(100 + index % 5_000)
            entries.append(expense(amount, on: day, category: categories[index % 12], merchant: "M\(index % 40)"))
        }
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for period in AnalyticsPeriod.allCases {
                _ = try report(entries, period)
            }
        }
        #expect(elapsed < .seconds(1), "All five periods took \(elapsed)")
    }

    /// Owner decision 2026-09-26: pending items dated up to now count when asked; cancelled and future never do.
    @Test func pendingItemsCountOnlyWhenIncluded() throws {
        let day = now.addingTimeInterval(-3_600)
        var pending = expense(1_000, on: day, category: nil, merchant: "Pending")
        pending.status = .pending
        var cancelled = expense(500, on: day, category: nil, merchant: "Cancelled")
        cancelled.status = .cancelled
        var future = expense(700, on: now.addingTimeInterval(86_400), category: nil, merchant: "Later")
        future.status = .pending
        let entries = [expense(4_750, on: day, category: nil, merchant: "Posted"), pending, cancelled, future]
        let excluded = try AnalyticsEngine().report(
            entries, period: .thisMonth, now: now, calendar: calendar, currencyCode: "CAD")
        let included = try AnalyticsEngine().report(
            entries, period: .thisMonth, now: now, calendar: calendar, currencyCode: "CAD", includePending: true)
        #expect(excluded.expense == Money(minorUnits: 4_750, currencyCode: "CAD"))
        #expect(included.expense == Money(minorUnits: 5_750, currencyCode: "CAD"))
    }
}
