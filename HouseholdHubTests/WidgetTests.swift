import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct WidgetTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func summary() -> DashboardSummary {
        let window = DateInterval(start: now, duration: 30 * 86_400)
        let balance = BalanceSnapshot(
            current: cad(248_050), pendingImpact: cad(-4_750), projected: cad(312_300), projectionWindow: window)
        let upcoming = (1...3).map { index in
            UpcomingOccurrence(
                seriesID: UUID(), date: now.addingTimeInterval(Double(index) * 86_400),
                amount: cad(-1_000 * Int64(index)), type: index == 2 ? .income : .expense, title: "Item \(index)")
        }
        return DashboardSummary(balance: balance, spentThisWeek: cad(0), upcoming: upcoming)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "widget-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func snapshotCarriesTheDashboardFiguresAndTheNextTwoItems() {
        let snapshot = WidgetSnapshot.make(from: summary(), showAmounts: true, now: now, calendar: calendar)
        #expect(snapshot.current == cad(248_050))
        #expect(snapshot.pendingImpact == cad(-4_750))
        #expect(snapshot.projected == cad(312_300))
        #expect(snapshot.projectionDays == 30)
        #expect(snapshot.upcoming.map(\.title) == ["Item 1", "Item 2"])
        #expect(snapshot.upcoming.map(\.amountMinorUnits) == [1_000, 2_000])
        #expect(snapshot.upcoming.map(\.isIncome) == [false, true])
    }

    @Test func hiddenAmountsLeaveNoAmountInTheFile() throws {
        let snapshot = WidgetSnapshot.make(from: summary(), showAmounts: false, now: now, calendar: calendar)
        #expect(snapshot.amountsHidden)
        #expect(snapshot.pendingImpact == nil && snapshot.projected == nil)
        let hasAmount = snapshot.upcoming.contains { $0.amountMinorUnits != nil }
        #expect(!hasAmount)
        let store = WidgetSnapshotStore(directory: temporaryDirectory())
        try store.write(snapshot)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(!text.contains("248050") && !text.contains("4750") && !text.contains("312300"))
    }

    @Test func storeRoundTripsAndRejectsDamagedFiles() throws {
        let directory = temporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.read() == nil)
        let snapshot = WidgetSnapshot.make(from: summary(), showAmounts: true, now: now, calendar: calendar)
        try store.write(snapshot)
        #expect(store.read() == snapshot)

        try Data("not json".utf8).write(to: store.url)
        #expect(store.read() == nil)

        let future = WidgetSnapshot(
            version: 2, generatedAt: now, currencyCode: "CAD", currentMinorUnits: 1, pendingImpactMinorUnits: 0,
            projectedMinorUnits: 1, projectionDays: 30, upcoming: [])
        try store.write(future)
        #expect(store.read() == nil)

        try Data(count: WidgetSnapshotStore.maxBytes + 1).write(to: store.url)
        #expect(store.read() == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test(arguments: [nil, "", "group.invalid.householdhub.test"])
    func withoutAnEntitledAppGroupTheFixtureIsUsed(_ identifier: String?) {
        #expect(WidgetSnapshotStore.appGroup(identifier) == nil)
        let provider = WidgetDataSource.provider(groupIdentifier: identifier)
        #expect(provider.snapshot(now: now) == WidgetSnapshot.sample(now: now))
    }

    @Test func widgetSettingDefaultsOnAndRoundTripsThroughBackups() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        func stored(_ container: ModelContainer) throws -> Bool {
            try #require(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first).widgetShowsBalance
        }
        #expect(try stored(container))
        try await ledger.setWidgetShowsBalance(false, now: now)
        #expect(try !stored(container))

        var backup = try await BackupService.make(container: container).snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.settings.widgetShowsBalance == false)
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        #expect(try !stored(target))
        // A backup from before the setting existed restores the default.
        backup.settings.widgetShowsBalance = nil
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        #expect(try stored(target))
    }
}
