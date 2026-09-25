import Foundation
import Testing

@testable import HouseholdHubCore

struct BalanceCalculatorTests {
    private typealias Series = RecurringSeries

    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func line(
        _ minorUnits: Int64, _ type: TransactionType, _ status: TransactionStatus, _ iso: String
    ) throws -> LedgerLine {
        LedgerLine(amount: cad(minorUnits), type: type, status: status, occurredAt: try date(iso))
    }

    private func monthly(_ day: Int, _ amount: Int64, _ type: TransactionType, from iso: String) throws -> Series {
        let start = try date(iso)
        let rule = RecurrenceRule.monthlyOnDay(day: day)
        return RecurringSeries(templateAmount: cad(amount), type: type, rule: rule, timeZone: zone, startDate: start)
    }

    /// Worked example (all CAD, minor units). Starting balance 100000 at 2026-09-01 00:00, now 2026-09-25 15:00.
    /// current  = 100000 + 50000 (income) - 4750 (expense)                           = 145250
    /// pending  = -2000 (expense) + 300000 (salary occurrence recorded as pending)  = 298000
    /// projected (pending excluded) = 145250 - 3000 (future-dated) - 120000 (rent Oct 1) = 22250
    /// projected (pending included) = 22250 + 298000                                 = 320250
    @Test(arguments: [(false, Int64(22250)), (true, 320_250)])
    func workedExampleMatchesSpecRules(includePending: Bool, expectedProjected: Int64) throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let startDate = try date("2026-09-01T00:00:00-07:00")
        let rent = try monthly(1, 120_000, .expense, from: "2026-01-01T09:00:00-08:00")
        let salary = try monthly(15, 300_000, .income, from: "2026-01-15T09:00:00-08:00")
        var gym = try monthly(20, 5000, .expense, from: "2026-01-20T09:00:00-08:00")
        gym.isEnabled = false
        var salaryOccurrence = try line(300_000, .income, .pending, "2026-10-15T09:00:00-07:00")
        salaryOccurrence.recurringSeriesID = salary.id
        salaryOccurrence.scheduledOccurrence = salaryOccurrence.occurredAt

        let lines = [
            try line(50_000, .income, .posted, "2026-09-05T12:00:00-07:00"),
            try line(4750, .expense, .posted, "2026-09-10T12:00:00-07:00"),
            try line(2000, .expense, .pending, "2026-09-12T12:00:00-07:00"),
            try line(99_900, .expense, .cancelled, "2026-09-13T12:00:00-07:00"),
            try line(10_000, .expense, .posted, "2026-08-30T12:00:00-07:00"),  // before the starting balance
            try line(7777, .expense, .posted, "2026-09-01T00:00:00-07:00"),  // at the starting instant: excluded
            try line(3000, .expense, .posted, "2026-10-01T12:00:00-07:00"),  // future-dated, inside the window
            try line(1111, .expense, .posted, "2026-10-30T16:00:00-07:00"),  // beyond the 30-day window
            salaryOccurrence,
        ]
        let snapshot = try BalanceCalculator().snapshot(
            startingBalance: cad(100_000), startingBalanceDate: startDate, lines: lines, series: [rent, salary, gym],
            now: now, calendar: calendar, includePendingInProjection: includePending)

        #expect(snapshot.current == cad(145_250))
        #expect(snapshot.pendingImpact == cad(298_000))
        #expect(snapshot.projected == cad(expectedProjected))
        let windowEnd = try date("2026-10-25T15:00:00-07:00")
        #expect(snapshot.projectionWindow == DateInterval(start: now, end: windowEnd))
    }

    @Test func projectionWindowIsHalfOpen() throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let dueNowAndAtWindowEnd = try monthly(25, 1000, .expense, from: "2026-09-25T15:00:00-07:00")
        let snapshot = try BalanceCalculator().snapshot(
            startingBalance: cad(0), startingBalanceDate: try date("2026-09-01T00:00:00-07:00"), lines: [],
            series: [dueNowAndAtWindowEnd], now: now, calendar: calendar, includePendingInProjection: false)
        #expect(snapshot.projected == cad(-1000))
    }

    @Test func cancelledMaterializationSkipsThatOccurrence() throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let rent = try monthly(1, 120_000, .expense, from: "2026-01-01T09:00:00-08:00")
        var skipped = try line(120_000, .expense, .cancelled, "2026-10-01T09:00:00-07:00")
        skipped.recurringSeriesID = rent.id
        skipped.scheduledOccurrence = skipped.occurredAt
        let snapshot = try BalanceCalculator().snapshot(
            startingBalance: cad(5000), startingBalanceDate: try date("2026-09-01T00:00:00-07:00"), lines: [skipped],
            series: [rent], now: now, calendar: calendar, includePendingInProjection: true)
        #expect(snapshot.current == cad(5000))
        #expect(snapshot.projected == cad(5000))
    }

    @Test func futurePostedOccurrenceIsCountedOnce() throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let rent = try monthly(1, 120_000, .expense, from: "2026-01-01T09:00:00-08:00")
        var prepaid = try line(120_000, .expense, .posted, "2026-10-01T09:00:00-07:00")
        prepaid.recurringSeriesID = rent.id
        prepaid.scheduledOccurrence = prepaid.occurredAt
        let snapshot = try BalanceCalculator().snapshot(
            startingBalance: cad(200_000), startingBalanceDate: try date("2026-09-01T00:00:00-07:00"), lines: [prepaid],
            series: [rent], now: now, calendar: calendar, includePendingInProjection: false)
        #expect(snapshot.current == cad(200_000))
        #expect(snapshot.projected == cad(80_000))
    }

    @Test func mixedCurrenciesAreRejected() throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let usd = LedgerLine(
            amount: Money(minorUnits: 100, currencyCode: "USD"), type: .expense, status: .posted,
            occurredAt: try date("2026-09-10T12:00:00-07:00"))
        #expect(throws: MoneyError.currencyMismatch("CAD", "USD")) {
            try BalanceCalculator().snapshot(
                startingBalance: cad(0), startingBalanceDate: try date("2026-09-01T00:00:00-07:00"), lines: [usd],
                series: [], now: now, calendar: calendar, includePendingInProjection: false)
        }
    }
}
