import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Settings › Household (v1 audit gap): §6.3 currency lock and §9.1 baseline corrections after onboarding.
struct HouseholdSettingsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeLedger() async throws -> (ModelContainer, TransactionService) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: now.addingTimeInterval(-86_400), now: now)
        return (container, ledger)
    }

    private func stored(_ container: ModelContainer) throws -> AppSettings {
        try #require(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
    }

    @Test func currencyChangesFreelyWhileNothingIsRecorded() async throws {
        let (container, ledger) = try await makeLedger()
        let locked = try await ledger.isCurrencyLocked()
        #expect(!locked)
        let balance = Money(minorUnits: 50_000, currencyCode: "USD")
        try await ledger.updateHousehold(currencyCode: "USD", startingBalance: balance, asOf: now, now: now)
        let settings = try stored(container)
        #expect(settings.currencyCode == "USD")
        #expect(settings.startingBalanceMinorUnits == 50_000)
    }

    @Test func recordsLockTheCurrencyAndARefusedChangeSavesNothing() async throws {
        let (container, ledger) = try await makeLedger()
        let spent = Money(minorUnits: 1_200, currencyCode: "CAD")
        try await ledger.create(
            TransactionDraft(amount: spent, type: .expense, occurredAt: now.addingTimeInterval(-60)), now: now)
        let locked = try await ledger.isCurrencyLocked()
        #expect(locked)
        let usd = Money(minorUnits: 9_900, currencyCode: "USD")
        await #expect(throws: LedgerError.currencyLockedByExistingRecords) {
            try await ledger.updateHousehold(currencyCode: "USD", startingBalance: usd, asOf: now, now: now)
        }
        let settings = try stored(container)
        #expect(settings.currencyCode == "CAD")
        #expect(settings.startingBalanceMinorUnits == 0, "A refused change leaves the baseline as it was")
    }

    @Test func theBaselineCanBeCorrectedWithRecordsAndMovesTheCurrentBalance() async throws {
        let (_, ledger) = try await makeLedger()
        let spent = Money(minorUnits: 1_200, currencyCode: "CAD")
        try await ledger.create(
            TransactionDraft(amount: spent, type: .expense, occurredAt: now.addingTimeInterval(-60)), now: now)
        let corrected = Money(minorUnits: 100_000, currencyCode: "CAD")
        let asOf = now.addingTimeInterval(-7 * 86_400)
        try await ledger.updateHousehold(currencyCode: "CAD", startingBalance: corrected, asOf: asOf, now: now)
        let snapshot = try #require(try await ledger.settingsSnapshot())
        #expect(snapshot.startingBalance == corrected)
        #expect(snapshot.startingBalanceDate == asOf)
    }

    @Test func aFutureDateOrAMismatchedAmountIsRefused() async throws {
        let (_, ledger) = try await makeLedger()
        let cad = Money(minorUnits: 100, currencyCode: "CAD")
        await #expect(throws: LedgerError.startingBalanceInFuture) {
            try await ledger.updateHousehold(
                currencyCode: "CAD", startingBalance: cad, asOf: now.addingTimeInterval(86_400), now: now)
        }
        await #expect(throws: LedgerError.currencyMismatch(expected: "USD", actual: "CAD")) {
            try await ledger.updateHousehold(currencyCode: "USD", startingBalance: cad, asOf: now, now: now)
        }
    }
}
