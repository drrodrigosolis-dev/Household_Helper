import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Editing and deleting a recurring series (v1 audit gap; spec §9.4: occurrences are computed, so a rule change moves
/// only the projection and never rewrites posted transactions).
struct RecurringSeriesEditTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func makeLedger() async throws -> (ModelContainer, TransactionService) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        return (container, ledger)
    }

    private func series(_ container: ModelContainer, _ id: UUID) throws -> RecurringTransaction {
        let all = try ModelContext(container).fetch(FetchDescriptor<RecurringTransaction>())
        return try #require(all.first { $0.id == id })
    }

    @Test func editingChangesFutureOccurrencesAndLeavesPostedOnesAlone() async throws {
        let (container, ledger) = try await makeLedger()
        let start = now.addingTimeInterval(-60 * 86_400)
        let id = try await ledger.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone,
            startDate: start, notes: "Rent", now: now)
        let first = try #require(try series(container, id).nextOccurrence)
        let posted = try await ledger.materialize(seriesID: id, occurrence: first, now: now)

        try await ledger.updateSeries(
            id, templateAmount: cad(130_000), type: .expense, rule: .monthlyOnDay(day: 15), startDate: start,
            categoryID: nil, notes: "Rent (new lease)", now: now)

        let edited = try series(container, id)
        #expect(edited.templateAmount == cad(130_000))
        #expect(edited.notes == "Rent (new lease)")
        let next = try #require(edited.nextOccurrence)
        #expect(next > first, "The next occurrence comes after the one already posted")
        #expect(HouseholdCalendar(timeZone: zone).calendar.component(.day, from: next) == 15)
        let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        let record = try #require(records.first { $0.id == posted })
        #expect(record.amount == cad(120_000), "A posted occurrence keeps its own amount")
        #expect(record.notes == "Rent")
    }

    @Test func editingIsValidatedLikeCreating() async throws {
        let (_, ledger) = try await makeLedger()
        let id = try await ledger.createSeries(
            templateAmount: cad(500), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: now,
            now: now)
        await #expect(throws: LedgerError.nonPositiveAmount) {
            try await ledger.updateSeries(
                id, templateAmount: cad(0), type: .expense, rule: .monthlyOnDay(day: 1), startDate: now,
                categoryID: nil, notes: nil, now: now)
        }
        await #expect(throws: LedgerError.transfersUnavailable) {
            try await ledger.updateSeries(
                id, templateAmount: cad(500), type: .transfer, rule: .monthlyOnDay(day: 1), startDate: now,
                categoryID: nil, notes: nil, now: now)
        }
        await #expect(throws: RecurrenceRuleError.self) {
            try await ledger.updateSeries(
                id, templateAmount: cad(500), type: .expense, rule: .monthlyOnDay(day: 40), startDate: now,
                categoryID: nil, notes: nil, now: now)
        }
        await #expect(throws: LedgerError.unknownSeries) {
            try await ledger.updateSeries(
                UUID(), templateAmount: cad(500), type: .expense, rule: .monthlyOnDay(day: 1), startDate: now,
                categoryID: nil, notes: nil, now: now)
        }
    }

    @Test func aSeriesIsDeletedOnlyWhileNothingWasPostedFromIt() async throws {
        let (container, ledger) = try await makeLedger()
        let start = now.addingTimeInterval(-40 * 86_400)
        let unused = try await ledger.createSeries(
            templateAmount: cad(999), type: .expense, rule: .monthlyOnDay(day: 3), timeZone: zone, startDate: start,
            now: now)
        try await ledger.deleteSeries(unused)
        #expect(try ModelContext(container).fetch(FetchDescriptor<RecurringTransaction>()).isEmpty)

        let used = try await ledger.createSeries(
            templateAmount: cad(4_500), type: .income, rule: .monthlyOnDay(day: 3), timeZone: zone, startDate: start,
            now: now)
        let occurrence = try #require(try series(container, used).nextOccurrence)
        try await ledger.materialize(seriesID: used, occurrence: occurrence, now: now)
        await #expect(throws: LedgerError.seriesHasHistory(postedCount: 1)) {
            try await ledger.deleteSeries(used)
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<RecurringTransaction>()).count == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>()).count == 1)
    }
}
