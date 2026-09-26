import Foundation
import Testing

@testable import HouseholdHubCore

struct RecurrenceEngineTests {
    private let vancouverZone = TimeZone(identifier: "America/Vancouver")!
    private let engine = RecurrenceEngine()

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func window(_ from: String, _ to: String) throws -> DateInterval {
        let start = try date(from)
        let end = try date(to)
        return DateInterval(start: start, end: end)
    }

    // DST edges use Europe/Berlin: tzdata 2026c keeps America/Vancouver on UTC-7 after March 2026, so its
    // offsets from November 2026 on depend on the host's time zone database.
    private let berlinZone = TimeZone(identifier: "Europe/Berlin")!

    private func series(
        _ rule: RecurrenceRule, start: String, end: String? = nil, zone: TimeZone? = nil
    ) throws -> RecurringSeries {
        let startDate = try date(start)
        let endDate = try end.map { try date($0) }
        let amount = Money(minorUnits: 1000, currencyCode: "CAD")
        return RecurringSeries(
            templateAmount: amount, type: .expense, rule: rule, timeZone: zone ?? vancouverZone,
            startDate: startDate, endDate: endDate)
    }

    /// Year, month, day and hour of each date in `zone`, independent of the zone's UTC offset.
    private func localParts(_ dates: [Date], in zone: TimeZone) -> [[Int]] {
        let calendar = HouseholdCalendar(timeZone: zone).calendar
        return dates.map { date in
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return [parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0]
        }
    }

    private func occurrences(_ series: RecurringSeries, _ window: DateInterval) -> [Date] {
        engine.occurrences(of: series, in: window)
    }

    @Test func monthlyDay31ClampsToShortMonths() throws {
        let rule = try series(.monthlyOnDay(day: 31), start: "2026-01-31T10:00:00-08:00")
        let result = occurrences(rule, try window("2026-01-01T00:00:00-08:00", "2026-05-01T00:00:00-07:00"))
        let expected = try [
            "2026-01-31T10:00:00-08:00", "2026-02-28T10:00:00-08:00", "2026-03-31T10:00:00-07:00",
            "2026-04-30T10:00:00-07:00",
        ].map(date)
        #expect(result == expected)
    }

    @Test(arguments: [
        ("2026-01-31T10:00:00-08:00", "2026-02-28T10:00:00-08:00"),
        ("2024-01-31T10:00:00-08:00", "2024-02-29T10:00:00-08:00"),
    ])
    func monthlyDay31NextOccurrenceHonoursLeapYears(start: String, expected: String) throws {
        let rule = try series(.monthlyOnDay(day: 31), start: start)
        let startDate = try date(start)
        let expectedDate = try date(expected)
        #expect(engine.nextOccurrence(of: rule, after: startDate) == expectedDate)
    }

    @Test func yearlyFeb29FallsOnFeb28InCommonYears() throws {
        let rule = try series(.yearly(month: 2, day: 29), start: "2024-02-29T09:00:00-08:00")
        let result = occurrences(rule, try window("2024-01-01T00:00:00-08:00", "2029-01-01T00:00:00Z"))
        let expected = [[2024, 2, 29, 9], [2025, 2, 28, 9], [2026, 2, 28, 9], [2027, 2, 28, 9], [2028, 2, 29, 9]]
        #expect(localParts(result, in: vancouverZone) == expected)
    }

    @Test func biweeklyKeepsLocalTimeAcrossFallBack() throws {
        let rule = try series(.weekly(interval: 2, weekday: 6), start: "2026-10-09T09:00:00+02:00", zone: berlinZone)
        let result = occurrences(rule, try window("2026-10-01T00:00:00+02:00", "2026-11-30T00:00:00+01:00"))
        let expected = try [
            "2026-10-09T09:00:00+02:00", "2026-10-23T09:00:00+02:00", "2026-11-06T09:00:00+01:00",
            "2026-11-20T09:00:00+01:00",
        ].map(date)
        #expect(result == expected)
    }

    @Test func weeklyStartsOnFirstMatchingWeekdayOnOrAfterStart() throws {
        let rule = try series(.weekly(interval: 1, weekday: 6), start: "2026-09-23T08:00:00-07:00")
        let result = occurrences(rule, try window("2026-09-01T00:00:00-07:00", "2026-10-03T00:00:00-07:00"))
        let expected = try ["2026-09-25T08:00:00-07:00", "2026-10-02T08:00:00-07:00"].map(date)
        #expect(result == expected)
    }

    @Test func nthAndLastWeekdayOfMonth() throws {
        let lastFriday = try series(.monthlyOnWeekday(ordinal: -1, weekday: 6), start: "2026-09-01T12:00:00-07:00")
        let september = try window("2026-09-01T00:00:00-07:00", "2026-10-01T00:00:00-07:00")
        let sept25 = try date("2026-09-25T12:00:00-07:00")
        #expect(occurrences(lastFriday, september) == [sept25])

        let secondTuesday = try series(.monthlyOnWeekday(ordinal: 2, weekday: 3), start: "2026-09-01T12:00:00-07:00")
        let october = try window("2026-10-01T00:00:00-07:00", "2026-11-01T00:00:00-07:00")
        let oct13 = try date("2026-10-13T12:00:00-07:00")
        #expect(occurrences(secondTuesday, october) == [oct13])
    }

    @Test func seriesStartAndInclusiveEndBoundOccurrences() throws {
        let lastDay = "2026-03-01T09:00:00-08:00"
        let bounded = try series(.monthlyOnDay(day: 1), start: "2026-01-01T09:00:00-08:00", end: lastDay)
        let year = try window("2025-06-01T00:00:00-07:00", "2027-01-01T00:00:00-08:00")
        let expected = try ["2026-01-01T09:00:00-08:00", "2026-02-01T09:00:00-08:00", lastDay].map(date)
        #expect(occurrences(bounded, year) == expected)

        let lateStart = try series(.monthlyOnDay(day: 15), start: "2026-01-20T09:00:00-08:00")
        let firstQuarter = try window("2026-01-01T00:00:00-08:00", "2026-03-01T00:00:00-08:00")
        let feb15 = try date("2026-02-15T09:00:00-08:00")
        #expect(occurrences(lateStart, firstQuarter) == [feb15])
    }

    @Test func disabledSeriesHasNoOccurrences() throws {
        var rule = try series(.monthlyOnDay(day: 1), start: "2026-01-01T09:00:00-08:00")
        rule.isEnabled = false
        let year = try window("2026-01-01T00:00:00-08:00", "2027-01-01T00:00:00-08:00")
        #expect(occurrences(rule, year).isEmpty)
    }

    @Test func skippedLocalTimeResolvesOnTheSameDay() throws {
        let rule = try series(.monthlyOnDay(day: 8), start: "2026-02-08T02:30:00-08:00")
        let march = try window("2026-03-01T00:00:00-08:00", "2026-04-01T00:00:00-07:00")
        let result = occurrences(rule, march)
        #expect(result.count == 1)
        let calendar = HouseholdCalendar(timeZone: vancouverZone)
        let occurrence = try #require(result.first)
        #expect(calendar.calendar.component(.day, from: occurrence) == 8)
        #expect(calendar.calendar.component(.hour, from: occurrence) >= 3)
    }

    @Test func farFutureWindowDoesNotIterateFromSeriesStart() throws {
        let rule = try series(.weekly(interval: 1, weekday: 2), start: "2000-01-03T09:00:00-08:00")
        let result = occurrences(rule, try window("2026-09-01T00:00:00-07:00", "2026-09-15T00:00:00-07:00"))
        let expected = try ["2026-09-07T09:00:00-07:00", "2026-09-14T09:00:00-07:00"].map(date)
        #expect(result == expected)
    }

    @Test(arguments: [
        RecurrenceRule.weekly(interval: 0, weekday: 2), .weekly(interval: 1, weekday: 8), .monthlyOnDay(day: 32),
        .monthlyOnWeekday(ordinal: 5, weekday: 2), .yearly(month: 2, day: 30), .yearly(month: 13, day: 1),
    ])
    func invalidRulesAreRejected(rule: RecurrenceRule) {
        #expect(throws: RecurrenceRuleError.self) { try rule.validate() }
    }

    @Test(arguments: [
        RecurrenceRule.weekly(interval: 2, weekday: 6), .monthlyOnDay(day: 31),
        .monthlyOnWeekday(ordinal: -1, weekday: 6), .yearly(month: 2, day: 29),
    ])
    func rulesRoundTripThroughStorageEncoding(rule: RecurrenceRule) throws {
        #expect(try RecurrenceRule.decoded(from: rule.encoded()) == rule)
    }
}
