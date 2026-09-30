import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Audit A-001 end to end (Sprint 23 review B1): a bill set up "now", with fractions of a second, is due today,
/// shows in Upcoming, and posts exactly once.
struct Sprint23RecurrenceTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    @Test func aBillStartedNowIsDueTodayAndPostsOnce() async throws {
        // Sunday 2026-09-27 20:45:12 Vancouver, plus a fraction of a second as Date.now has.
        let whole = try #require(ISO8601DateFormatter().date(from: "2026-09-27T20:45:12-07:00"))
        let start = whole.addingTimeInterval(0.734)
        let now = start.addingTimeInterval(90)
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(100_000), asOf: now.addingTimeInterval(-30 * 86_400), now: now)

        let id = try await ledger.createSeries(
            templateAmount: cad(1_799), type: .expense, rule: .monthlyOnDay(day: 27), timeZone: zone,
            startDate: start, notes: "Netflix", now: now)
        let series = try #require(
            try ModelContext(container).fetch(FetchDescriptor<RecurringTransaction>()).first { $0.id == id })
        #expect(series.nextOccurrence == whole, "Today's occurrence is the next one")

        let upcoming = try await ledger.upcomingOccurrences(now: now, calendar: calendar, days: 7)
        #expect(upcoming.contains { $0.seriesID == id && $0.date == whole })

        try await ledger.materialize(seriesID: id, occurrence: whole, now: now)
        await #expect(throws: LedgerError.alreadyMaterialized) {
            try await ledger.materialize(seriesID: id, occurrence: whole, now: now)
        }
    }
}
