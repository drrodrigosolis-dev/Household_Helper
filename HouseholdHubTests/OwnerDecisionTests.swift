import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Tests for the owner's 2026-09-26 decisions (docs/PROGRESS.md, items 6-11): Analytics pending, the Shortcut
/// source in backups, and the accent visibility rule.
struct OwnerDecisionTests {
    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!, firstWeekday: 2)
    private var now: Date {
        var parts = DateComponents(year: 2026, month: 9, day: 26, hour: 12)
        parts.timeZone = calendar.timeZone
        return calendar.calendar.date(from: parts)!
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private struct Stack {
        let container: ModelContainer
        let ledger: TransactionService
        let analytics: AnalyticsService
        let backup: BackupService
    }

    private func makeStack() async throws -> Stack {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let stack = Stack(
            container: container, ledger: .make(container: container), analytics: .make(container: container),
            backup: .make(container: container))
        try await stack.ledger.ensureSettings(currencyCode: "CAD", now: now)
        return stack
    }

    // MARK: Analytics pending (decision 6)

    @Test func theStoredSwitchDecidesWhetherPendingCounts() async throws {
        let stack = try await makeStack()
        let hourAgo = now.addingTimeInterval(-3_600)
        try await stack.ledger.create(
            TransactionDraft(amount: cad(4_750), type: .expense, occurredAt: hourAgo), now: now)
        try await stack.ledger.create(
            TransactionDraft(amount: cad(1_000), type: .expense, occurredAt: hourAgo, status: .pending), now: now)
        let off = try await stack.analytics.report(period: .thisMonth, now: now, calendar: calendar)
        #expect(off.expense == cad(4_750))
        try await stack.ledger.setAnalyticsIncludesPending(true, now: now)
        let on = try await stack.analytics.report(period: .thisMonth, now: now, calendar: calendar)
        #expect(on.expense == cad(5_750))
    }

    struct PendingCase: Sendable, CustomTestStringConvertible {
        let label: String
        let type: TransactionType
        let secondsFromNow: Double
        let counted: Bool
        var testDescription: String { label }
    }

    static let pendingCases = [
        PendingCase(label: "pending income", type: .income, secondsFromNow: -3_600, counted: true),
        PendingCase(label: "pending expense dated now", type: .expense, secondsFromNow: 0, counted: true),
        PendingCase(label: "pending expense tomorrow", type: .expense, secondsFromNow: 86_400, counted: false),
        PendingCase(label: "pending transfer", type: .transfer, secondsFromNow: -3_600, counted: false),
    ]

    @Test(arguments: pendingCases)
    func pendingItemsCountOnlyWhenTheyHaveHappened(_ entry: PendingCase) throws {
        let when = now.addingTimeInterval(entry.secondsFromNow)
        let item = AnalyticsEntry(amount: cad(1_000), type: entry.type, status: .pending, occurredAt: when)
        let report = try AnalyticsEngine().report(
            [item], period: .thisMonth, now: now, calendar: calendar, currencyCode: "CAD", includePending: true)
        let total = entry.type == .income ? report.income : report.expense
        #expect(total == cad(entry.counted ? 1_000 : 0))
    }

    @Test func theSwitchBacksUpAndOlderBackupsReadItAsOff() async throws {
        let stack = try await makeStack()
        try await stack.ledger.setAnalyticsIncludesPending(true, now: now)
        var backup = try await stack.backup.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.settings.analyticsIncludesPending == true)
        let target = try await makeStack()
        _ = try await target.backup.restore(backup, availableMedia: [], now: now)
        func stored() throws -> Bool {
            try #require(try ModelContext(target.container).fetch(FetchDescriptor<AppSettings>()).first)
                .analyticsIncludesPending
        }
        #expect(try stored())
        backup.settings.analyticsIncludesPending = nil
        _ = try await target.backup.restore(backup, availableMedia: [], now: now)
        #expect(try !stored())
    }

    // MARK: Transaction sources in backups (decision 10)

    static let restorableSources: [TransactionSource] = [.manual, .imported, .widget, .naturalLanguage, .shortcut]

    @Test(arguments: restorableSources)
    func everyFreeStandingSourceValidatesAndRestores(_ source: TransactionSource) async throws {
        let stack = try await makeStack()
        try await stack.ledger.create(
            TransactionDraft(amount: cad(500), type: .expense, occurredAt: now.addingTimeInterval(-60)), now: now)
        var backup = try await stack.backup.snapshot(now: now, appVersion: "1") { _ in nil }
        backup.transactions[0].source = source.rawValue
        try BackupValidator.validate(backup)
        let target = try await makeStack()
        _ = try await target.backup.restore(backup, availableMedia: [], now: now)
        let records = try ModelContext(target.container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.map(\.source) == [source])
    }

    // MARK: Accent visibility (decision 11)

    @Test func accentVisibilityFlagsColorsHardToSeeOnEitherBackground() throws {
        #expect(try #require(ColorToken(hex: "#EF6C00")).accentVisibility == .fine)
        #expect(try #require(ColorToken(hex: "#FFEB3B")).accentVisibility == .hardInLightMode)
        #expect(try #require(ColorToken(hex: "#4527A0")).accentVisibility == .hardInDarkMode)
    }
}
