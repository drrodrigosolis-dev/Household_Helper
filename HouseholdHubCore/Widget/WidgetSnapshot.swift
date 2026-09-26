import Foundation

/// What the Home Screen widget shows (spec §24.4), computed by the app from the same figures as the Dashboard and
/// handed to the extension as a small JSON file. The widget never opens the store, so it can't change records and
/// there is no second container (Sprint 8 default 1).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// The widget's kind, shared by the extension and the app's reload call.
    public static let widgetKind = "HouseholdHubSummary"
    /// Opens the Quick Add sheet (spec §24.4); a custom URL scheme needs no entitlement.
    public static let quickAddURL = URL(string: "householdhub://quickadd")!
    /// Info.plist key holding the App Group identifier (build setting `HH_APP_GROUP`, empty by default).
    public static let appGroupInfoKey = "HHAppGroup"

    public struct Upcoming: Codable, Equatable, Sendable {
        public let title: String?
        public let date: Date
        /// Positive magnitude in minor units; nil when amounts are hidden.
        public let amountMinorUnits: Int64?
        public let isIncome: Bool

        public init(title: String?, date: Date, amountMinorUnits: Int64?, isIncome: Bool) {
            self.title = title
            self.date = date
            self.amountMinorUnits = amountMinorUnits
            self.isIncome = isIncome
        }
    }

    public let version: Int
    public let generatedAt: Date
    public let currencyCode: String
    /// Nil when the user hid amounts (`widgetShowsBalance` off): the file then carries no amounts at all.
    public let currentMinorUnits: Int64?
    public let pendingImpactMinorUnits: Int64?
    public let projectedMinorUnits: Int64?
    public let projectionDays: Int
    /// At most two, soonest first (§24.4 medium).
    public let upcoming: [Upcoming]

    public init(
        version: Int = currentVersion, generatedAt: Date, currencyCode: String, currentMinorUnits: Int64?,
        pendingImpactMinorUnits: Int64?, projectedMinorUnits: Int64?, projectionDays: Int, upcoming: [Upcoming]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.currencyCode = currencyCode
        self.currentMinorUnits = currentMinorUnits
        self.pendingImpactMinorUnits = pendingImpactMinorUnits
        self.projectedMinorUnits = projectedMinorUnits
        self.projectionDays = projectionDays
        self.upcoming = upcoming
    }

    public var amountsHidden: Bool { currentMinorUnits == nil }

    public var current: Money? { currentMinorUnits.map { Money(minorUnits: $0, currencyCode: currencyCode) } }
    public var pendingImpact: Money? {
        pendingImpactMinorUnits.map { Money(minorUnits: $0, currencyCode: currencyCode) }
    }
    public var projected: Money? { projectedMinorUnits.map { Money(minorUnits: $0, currencyCode: currencyCode) } }

    /// The widget's view of `summary`. With `showAmounts` off, every amount and every item title is left out.
    public static func make(
        from summary: DashboardSummary, showAmounts: Bool, now: Date, calendar: HouseholdCalendar
    ) -> WidgetSnapshot {
        let balance = summary.balance
        let days = calendar.calendar.dateComponents(
            [.day], from: balance.projectionWindow.start, to: balance.projectionWindow.end
        ).day ?? 30
        let upcoming = summary.upcoming.prefix(2).map { item in
            Upcoming(
                title: showAmounts ? item.title : nil, date: item.date,
                amountMinorUnits: showAmounts ? abs(item.amount.minorUnits) : nil, isIncome: item.type == .income)
        }
        return WidgetSnapshot(
            generatedAt: now, currencyCode: balance.current.currencyCode,
            currentMinorUnits: showAmounts ? balance.current.minorUnits : nil,
            pendingImpactMinorUnits: showAmounts ? balance.pendingImpact.minorUnits : nil,
            projectedMinorUnits: showAmounts ? balance.projected.minorUnits : nil, projectionDays: days,
            upcoming: Array(upcoming))
    }

    /// No amounts and no items: what a live widget shows before the app has written a snapshot, or after it failed
    /// to compute one. Never invented figures.
    public static func placeholder(now: Date, currencyCode: String = "CAD") -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now, currencyCode: currencyCode, currentMinorUnits: nil, pendingImpactMinorUnits: nil,
            projectedMinorUnits: nil, projectionDays: 30, upcoming: [])
    }

    /// Items still ahead of `now`; a widget that isn't reloaded must not list past items as upcoming.
    public func upcoming(from now: Date, calendar: HouseholdCalendar) -> [Upcoming] {
        let today = calendar.startOfDay(for: now)
        return upcoming.filter { $0.date >= today }
    }

    /// Fixture for the simulator, previews, and the free Personal Team, where no App Group exists (spec §5.2).
    public static func sample(now: Date) -> WidgetSnapshot {
        let day: TimeInterval = 86_400
        return WidgetSnapshot(
            generatedAt: now, currencyCode: "CAD", currentMinorUnits: 248_050, pendingImpactMinorUnits: -4_750,
            projectedMinorUnits: 312_300, projectionDays: 30,
            upcoming: [
                Upcoming(
                    title: "Rent", date: now.addingTimeInterval(3 * day), amountMinorUnits: 180_000, isIncome: false),
                Upcoming(
                    title: "Paycheck", date: now.addingTimeInterval(5 * day), amountMinorUnits: 240_000,
                    isIncome: true),
            ])
    }
}

/// Where the widget gets its snapshot (spec §5.2).
public protocol WidgetDataProvider: Sendable {
    func snapshot(now: Date) -> WidgetSnapshot
}

/// Simulator / preview / free-team data: always the fixture (§5.2).
public struct FreeDevelopmentWidgetDataProvider: WidgetDataProvider {
    public init() {}

    public func snapshot(now: Date) -> WidgetSnapshot {
        .sample(now: now)
    }
}

/// Reads the app's snapshot from the App Group container. Used only when an App Group identifier is configured and
/// the container actually exists (the entitlement is present); otherwise `make` returns nil and callers fall back
/// to `FreeDevelopmentWidgetDataProvider`.
public struct AppGroupWidgetDataProvider: WidgetDataProvider {
    public let store: WidgetSnapshotStore

    public init(store: WidgetSnapshotStore) {
        self.store = store
    }

    public static func make(groupIdentifier: String?) -> AppGroupWidgetDataProvider? {
        guard let store = WidgetSnapshotStore.appGroup(groupIdentifier) else { return nil }
        return AppGroupWidgetDataProvider(store: store)
    }

    /// The saved snapshot, or an amount-free placeholder until the app has written one. A live widget never shows
    /// the fixture's invented figures, and a missing or unreadable file never shows an error on the Home Screen.
    public func snapshot(now: Date) -> WidgetSnapshot {
        store.read() ?? .placeholder(now: now)
    }
}

public enum WidgetDataSource {
    /// The provider for this build: the App Group one when available, else the fixture.
    public static func provider(groupIdentifier: String?) -> any WidgetDataProvider {
        AppGroupWidgetDataProvider.make(groupIdentifier: groupIdentifier) ?? FreeDevelopmentWidgetDataProvider()
    }
}
