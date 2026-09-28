import Foundation
import HouseholdHubCore
import SwiftData
import Testing

@testable import HouseholdHub

/// Sprint 23 (F6): Budget's amount range, custom dates and account filters, and saved searches kept as a device
/// setting.
struct Sprint23SearchFilterTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    private let calendar = Sprint23SearchFilterTests.calendar
    /// Sunday 2026-09-27, noon in Vancouver.
    private let now: Date = Sprint23SearchFilterTests.date(2026, 9, 27)

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func record(
        _ minorUnits: Int64, on date: Date? = nil, type: TransactionType = .expense, account: UUID? = nil,
        to destination: UUID? = nil
    ) -> TransactionRecord {
        let record = TransactionRecord(
            amount: cad(minorUnits), type: type, status: .posted, source: .manual, occurredAt: date ?? now, now: now)
        record.accountID = account
        record.transferAccountID = destination
        return record
    }

    /// The ids the filter's store query returns from `records`.
    private func fetch(_ filter: TransactionFilter, from records: [TransactionRecord]) throws -> Set<UUID> {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        for record in records {
            context.insert(record)
        }
        try context.save()
        return Set(try context.fetch(filter.fetchDescriptor(now: now, calendar: calendar)).map(\.id))
    }

    // MARK: Amount range

    /// Minimum, maximum, and the amounts listed out of 5.00, 12.50 and 50.00.
    static let amountCases: [(Int64?, Int64?, [Int64])] = [
        (nil, nil, [500, 1_250, 5_000]),
        (1_000, nil, [1_250, 5_000]),
        (nil, 1_250, [500, 1_250]),
        (1_000, 2_000, [1_250]),
        (1_250, 1_250, [1_250]),
        (6_000, nil, []),
    ]

    @Test(arguments: Sprint23SearchFilterTests.amountCases)
    func amountRangeIncludesBothEnds(minimum: Int64?, maximum: Int64?, expected: [Int64]) throws {
        let records = [record(500), record(1_250), record(5_000, type: .income)]
        let filter = TransactionFilter(minimumAmountMinorUnits: minimum, maximumAmountMinorUnits: maximum)
        let found = try fetch(filter, from: records)
        #expect(Set(records.filter { found.contains($0.id) }.map(\.amountMinorUnits)) == Set(expected))
        #expect(filter.isActive == (minimum != nil || maximum != nil))
    }

    // MARK: Custom dates

    @Test func dateRangeIncludesItsStartAndExcludesItsEnd() throws {
        let start = calendar.startOfDay(for: Self.date(2026, 9, 15))
        let end = calendar.startOfDay(for: Self.date(2026, 9, 21))
        let before = record(100, on: start.addingTimeInterval(-1))
        let first = record(200, on: start)
        let inside = record(300, on: Self.date(2026, 9, 20, hour: 23))
        let atEnd = record(400, on: end)
        let filter = TransactionFilter(dateRange: DateInterval(start: start, end: end))
        #expect(try fetch(filter, from: [before, first, inside, atEnd]) == [first.id, inside.id])
    }

    @Test func dateRangeNarrowsThePeriodToo() throws {
        // This month and a range reaching back into August: only September's part of the range counts.
        let august = record(100, on: Self.date(2026, 8, 30))
        let september = record(200, on: Self.date(2026, 9, 2))
        let range = DateInterval(start: Self.date(2026, 8, 25), end: Self.date(2026, 9, 10))
        let filter = TransactionFilter(period: .thisMonth, dateRange: range)
        #expect(try fetch(filter, from: [august, september]) == [september.id])
    }

    // MARK: Account

    @Test func accountFilterIncludesTransfersInAndOut() throws {
        let everyday = UUID()
        let savings = UUID()
        let spent = record(100, account: everyday)
        let saved = record(200, account: savings)
        let moved = record(300, type: .transfer, account: everyday, to: savings)
        let filter = TransactionFilter(accountID: savings)
        #expect(try fetch(filter, from: [spent, saved, moved]) == [saved.id, moved.id])
    }

    // MARK: Codable

    @Test func everyFilterFieldSurvivesARoundTrip() throws {
        let filter = TransactionFilter(
            period: .last30Days, categoryID: UUID(), status: .pending, accountID: UUID(), uncategorizedOnly: false,
            dateRange: DateInterval(start: Self.date(2026, 9, 1), end: Self.date(2026, 9, 15)),
            minimumAmountMinorUnits: 1_000, maximumAmountMinorUnits: 25_000)
        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(TransactionFilter.self, from: data) == filter)

        var uncategorized = TransactionFilter()
        uncategorized.categoryChoice = .uncategorized
        let again = try JSONDecoder().decode(TransactionFilter.self, from: try JSONEncoder().encode(uncategorized))
        #expect(again.categoryChoice == .uncategorized)
    }

    @Test func aFilterSavedByAnotherVersionStillReads() throws {
        let empty = try JSONDecoder().decode(TransactionFilter.self, from: Data("{}".utf8))
        #expect(empty == TransactionFilter(), "Missing fields read as no filter")
        let json = #"{"period":"fortnight","status":"posted","minimumAmountMinorUnits":500}"#
        let newer = try JSONDecoder().decode(TransactionFilter.self, from: Data(json.utf8))
        #expect(newer.period == .all, "A period this version doesn't know reads as all time")
        #expect(newer.status == .posted)
        #expect(newer.minimumAmountMinorUnits == 500)
    }

    // MARK: Saved searches

    private func makeStore() throws -> SavedSearchStore {
        let suite = "Sprint23SearchFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return SavedSearchStore(defaults: defaults)
    }

    @Test func savedSearchesKeepTheirTextAndFilter() throws {
        let store = try makeStore()
        #expect(store.all().isEmpty)
        let filter = TransactionFilter(period: .thisMonth, minimumAmountMinorUnits: 2_000)
        let groceries = try #require(store.save(name: " Big groceries ", text: "market ", filter: filter))
        store.save(name: "Pending", text: "", filter: TransactionFilter(status: .pending))

        let saved = store.all()
        #expect(saved.map(\.name) == ["Big groceries", "Pending"])
        #expect(saved.first == groceries)
        #expect(saved.first?.text == "market")
        #expect(saved.first?.filter == filter)
    }

    @Test func savingUnderAnExistingNameReplacesItInPlace() throws {
        let store = try makeStore()
        store.save(name: "Coffee", text: "coffee", filter: TransactionFilter())
        store.save(name: "Rent", text: "rent", filter: TransactionFilter())
        store.save(name: "coffee", text: "espresso", filter: TransactionFilter(period: .thisWeek))
        let saved = store.all()
        #expect(saved.map(\.name) == ["coffee", "Rent"])
        #expect(saved.first?.text == "espresso")
        #expect(store.save(name: "   ", text: "x", filter: TransactionFilter()) == nil, "A search needs a name")
    }

    @Test func deletingASavedSearchKeepsTheOthers() throws {
        let store = try makeStore()
        let coffee = try #require(store.save(name: "Coffee", text: "coffee", filter: TransactionFilter()))
        store.save(name: "Rent", text: "rent", filter: TransactionFilter())
        store.delete(id: coffee.id)
        #expect(store.all().map(\.name) == ["Rent"])
        store.removeAll()
        #expect(store.all().isEmpty)
    }

    @Test func corruptStorageReadsAsNoSavedSearches() throws {
        let suite = "Sprint23SearchFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(Data("not json".utf8), forKey: SavedSearchStore.key)
        #expect(SavedSearchStore(defaults: defaults).all().isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }
}
