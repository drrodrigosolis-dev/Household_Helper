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

    /// Without an identifier there is no store. An unentitled identifier may still get a container URL on the
    /// Simulator, which does not enforce App Group entitlements, so for it only the fallback is checked.
    @Test(arguments: [nil, "", "group.invalid.householdhub.test"])
    func withoutAnEntitledAppGroupTheFixtureIsUsed(_ identifier: String?) {
        let shown = WidgetDataSource.provider(groupIdentifier: identifier).snapshot(now: now)
        if identifier?.isEmpty ?? true {
            #expect(WidgetSnapshotStore.appGroup(identifier) == nil)
            #expect(shown == WidgetSnapshot.sample(now: now))
        } else {
            // Simulator: a container may exist without the entitlement; with no file, amounts are never invented.
            #expect(shown == WidgetSnapshot.sample(now: now) || shown == WidgetSnapshot.placeholder(now: now))
        }
    }

    @Test func aLiveWidgetWithoutASnapshotShowsNoFigures() {
        let provider = AppGroupWidgetDataProvider(store: WidgetSnapshotStore(directory: temporaryDirectory()))
        let shown = provider.snapshot(now: now)
        #expect(shown.amountsHidden && shown.upcoming.isEmpty)
    }

    @Test func pastItemsDropOutOfUpcoming() {
        let snapshot = WidgetSnapshot.make(from: summary(), showAmounts: true, now: now, calendar: calendar)
        let later = now.addingTimeInterval(2 * 86_400)
        #expect(snapshot.upcoming(from: later, calendar: calendar).map(\.title) == ["Item 2"])
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

/// The Log Transaction shortcut's parse-and-validate step (Sprint 8 review: the intent's write path needs tests).
struct ShortcutEntryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)

    private func settings(onboarded: Bool = true, currency: String = "CAD") -> SettingsSnapshot {
        SettingsSnapshot(
            currencyCode: currency, onboardingCompleted: onboarded,
            startingBalance: Money(minorUnits: 0, currencyCode: currency), startingBalanceDate: now,
            includePendingInProjection: false)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        let minorUnits: Int64
        let income: Bool
        let daysBack: Int
        let notes: String?
        var testDescription: String { text }
    }

    static let cases = [
        Case(text: "47.50 coffee", minorUnits: 4_750, income: false, daysBack: 0, notes: "coffee"),
        Case(text: "+ 1200 paycheck", minorUnits: 120_000, income: true, daysBack: 0, notes: "paycheck"),
        Case(text: "18 lunch yesterday", minorUnits: 1_800, income: false, daysBack: 1, notes: "lunch"),
        // A tag is dropped, not matched: the intent has no category list.
        Case(text: "32.10 groceries #food", minorUnits: 3_210, income: false, daysBack: 0, notes: "groceries"),
        Case(text: "12", minorUnits: 1_200, income: false, daysBack: 0, notes: nil),
    ]

    @Test(arguments: cases)
    func entriesBecomeWidgetSourcedDraftsInTheHouseholdCurrency(_ entry: Case) throws {
        let draft = try ShortcutEntry.draft(text: entry.text, settings: settings(), now: now, calendar: calendar)
        #expect(draft.amount == Money(minorUnits: entry.minorUnits, currencyCode: "CAD"))
        #expect(draft.type == (entry.income ? .income : .expense))
        #expect(draft.source == .widget)
        #expect(draft.categoryID == nil)
        #expect(draft.notes == entry.notes)
        #expect(draft.occurredAt == calendar.calendar.date(byAdding: .day, value: -entry.daysBack, to: now))
    }

    @Test func nothingIsDraftedWithoutAnAmountOrBeforeSetup() {
        #expect(throws: ShortcutEntryError.noAmount) {
            try ShortcutEntry.draft(text: "coffee", settings: settings(), now: now, calendar: calendar)
        }
        #expect(throws: ShortcutEntryError.notSetUp) {
            try ShortcutEntry.draft(text: "47.50 coffee", settings: nil, now: now, calendar: calendar)
        }
        #expect(throws: ShortcutEntryError.notSetUp) {
            try ShortcutEntry.draft(
                text: "47.50 coffee", settings: settings(onboarded: false), now: now, calendar: calendar)
        }
    }

    @Test func aShortcutDraftIsStoredOnceWithItsSource() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: now, now: now)
        let draft = try ShortcutEntry.draft(
            text: "47.50 coffee", settings: try await ledger.settingsSnapshot(), now: now, calendar: calendar)
        try await ledger.create(draft, now: now)
        let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.source == .widget)
    }

    /// The widget's figures are the Dashboard's, and hiding amounts removes them (Sprint 8 review).
    @Test func serviceSnapshotMatchesTheDashboardAndHonoursTheSwitch() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: Money(minorUnits: 100_000, currencyCode: "CAD"),
            asOf: now.addingTimeInterval(-30 * 86_400), now: now)
        let cad = { (minor: Int64) in Money(minorUnits: minor, currencyCode: "CAD") }
        try await ledger.create(
            TransactionDraft(amount: cad(4_750), type: .expense, occurredAt: now.addingTimeInterval(-3_600)), now: now)
        try await ledger.create(
            TransactionDraft(
                amount: cad(1_000), type: .expense, occurredAt: now.addingTimeInterval(-7_200), status: .pending),
            now: now)
        let summary = try await ledger.dashboardSummary(now: now, calendar: calendar)
        let shown = try await ledger.widgetSnapshot(now: now, calendar: calendar)
        #expect(shown == WidgetSnapshot.make(from: summary, showAmounts: true, now: now, calendar: calendar))
        #expect(shown.current == cad(95_250))
        try await ledger.setWidgetShowsBalance(false, now: now)
        let hidden = try await ledger.widgetSnapshot(now: now, calendar: calendar)
        #expect(hidden.amountsHidden && hidden.pendingImpact == nil && hidden.projected == nil)
    }
}

/// Sprint 9 settings: appearance and Quick Add default persist, back up, and restore; old backups read defaults.
struct PreferenceSettingsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func appearanceAndQuickAddDefaultRoundTripThroughBackups() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        func stored(_ container: ModelContainer) throws -> AppSettings {
            try #require(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        }
        let fresh = try stored(container)
        #expect(fresh.selectedTheme == .system && fresh.accentColor == nil && fresh.defaultQuickAddType == .expense)

        let purple = try #require(ColorToken(hex: "#6A1B9A"))
        try await ledger.setAppearance(theme: .dark, accent: purple, now: now)
        try await ledger.setDefaultQuickAddType(.task, now: now)
        var backup = try await BackupService.make(container: container).snapshot(now: now, appVersion: "1") { _ in nil }
        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        let restored = try stored(target)
        #expect(restored.selectedTheme == .dark && restored.accentColor == purple)
        #expect(restored.defaultQuickAddType == .task)

        backup.settings.selectedTheme = nil
        backup.settings.accentColorHex = nil
        backup.settings.defaultQuickAddType = "somethingNew"
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        let defaults = try stored(target)
        #expect(defaults.selectedTheme == .system && defaults.accentColor == nil)
        #expect(defaults.defaultQuickAddType == .expense, "An unknown value reads as the default")
    }
}
