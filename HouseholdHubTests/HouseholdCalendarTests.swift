import Foundation
import Testing

@testable import HouseholdHubCore

struct HouseholdCalendarTests {
    private let vancouver = HouseholdCalendar(
        timeZone: TimeZone(identifier: "America/Vancouver")!, locale: Locale(identifier: "en_CA"), firstWeekday: 2)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test(arguments: [
        ("2026-03-08T12:00:00-07:00", 23.0),  // spring forward
        ("2026-11-01T12:00:00-08:00", 25.0),  // fall back
        ("2026-09-25T12:00:00-07:00", 24.0),
    ])
    func dayBoundsFollowTheStoredTimeZoneAcrossDST(iso: String, hours: Double) throws {
        let noon = try date(iso)
        let start = vancouver.startOfDay(for: noon)
        let end = vancouver.endOfDay(for: noon)
        #expect(start <= noon && noon < end)
        #expect(end.timeIntervalSince(start) == hours * 3600)
    }

    @Test func monthYearAndWeekBounds() throws {
        let jan31 = try date("2026-01-31T10:00:00-08:00")
        let jan1 = try date("2026-01-01T00:00:00-08:00")
        let feb1 = try date("2026-02-01T00:00:00-08:00")
        #expect(vancouver.startOfMonth(for: jan31) == jan1)
        #expect(vancouver.endOfMonth(for: jan31) == feb1)
        #expect(vancouver.startOfYear(for: jan31) == jan1)

        let leapFeb = try date("2024-02-10T10:00:00-08:00")
        let leapMar1 = try date("2024-03-01T00:00:00-08:00")
        #expect(vancouver.endOfMonth(for: leapFeb) == leapMar1)

        let friday = try date("2026-09-25T15:00:00-07:00")
        let monday = try date("2026-09-21T00:00:00-07:00")
        #expect(vancouver.startOfWeek(for: friday) == monday)
    }

    @Test(arguments: [
        ("2026-09-25T00:10:00-07:00", RelativeDay.today),
        ("2026-09-26T03:00:00Z", .today),  // 20:00 in Vancouver: still today locally, tomorrow in UTC
        ("2026-09-24T23:30:00-07:00", .yesterday),
        ("2026-09-26T09:00:00-07:00", .tomorrow),
        ("2026-09-21T09:00:00-07:00", .earlierThisWeek(weekday: 2)),
        ("2026-09-18T09:00:00-07:00", .other),
        ("2026-09-28T09:00:00-07:00", .other),
    ])
    func relativeDayUsesLocalCalendarDays(iso: String, expected: RelativeDay) throws {
        let now = try date("2026-09-25T15:00:00-07:00")
        let target = try date(iso)
        #expect(vancouver.relativeDay(for: target, now: now) == expected)
    }
}
