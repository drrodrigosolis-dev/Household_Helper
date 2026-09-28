import Foundation
import SwiftData
import Synchronization

/// Read-only analytics (spec §2, §4.4): fetches one period's transactions on its own executor, off the main actor,
/// and hands them to the pure `AnalyticsEngine`. It never writes.
@ModelActor
public actor AnalyticsService {
    private static let instances = Mutex<[ObjectIdentifier: AnalyticsService]>([:])

    public static func make(container: ModelContainer) -> AnalyticsService {
        instances.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let service = AnalyticsService(modelContainer: container)
            cache[ObjectIdentifier(container)] = service
            return service
        }
    }

    public func report(period: AnalyticsPeriod, now: Date, calendar: HouseholdCalendar) throws -> AnalyticsReport {
        let settings = try requireSettings()
        let interval = period.interval(now: now, calendar: calendar)
        let entries = try fetchEntries(in: interval, now: now)
        return try AnalyticsEngine().report(
            entries, period: period, now: now, calendar: calendar, currencyCode: settings.currencyCode,
            includePending: settings.analyticsIncludesPending)
    }

    /// Each category of a single-month period against the month before (Sprint 23, A-018), in the report's order;
    /// empty for longer periods. Same rules as `report`: the previous month's figures are its spending after refunds.
    public func categoryChanges(
        period: AnalyticsPeriod, now: Date, calendar: HouseholdCalendar
    ) throws -> [CategoryChange] {
        guard let previous = period.comparisonInterval(now: now, calendar: calendar) else { return [] }
        let settings = try requireSettings()
        let interval = period.interval(now: now, calendar: calendar)
        let entries = try fetchEntries(in: DateInterval(start: previous.start, end: interval.end), now: now)
        let engine = AnalyticsEngine()
        let code = settings.currencyCode
        let pending = settings.analyticsIncludesPending
        let current = try engine.report(
            entries, interval: interval, bucket: period.bucket, now: now, calendar: calendar, currencyCode: code,
            includePending: pending)
        let before = try engine.report(
            entries, interval: previous, bucket: period.bucket, now: now, calendar: calendar, currencyCode: code,
            includePending: pending)
        return try engine.changes(from: before.byCategory, to: current.byCategory)
    }

    private func requireSettings() throws -> AppSettings {
        var settingsDescriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        guard let settings = try modelContext.fetch(settingsDescriptor).first else { throw LedgerError.settingsMissing }
        return settings
    }

    /// Every transaction in `interval` dated up to `now`, as analytics entries.
    private func fetchEntries(in interval: DateInterval, now: Date) throws -> [AnalyticsEntry] {
        let start = interval.start
        let end = min(interval.end, now.addingTimeInterval(1))
        // Fetched by date only: status is checked after `ledgerLine()`, so an unreadable stored status fails the
        // read loudly (as balances do) instead of being silently left out by the store query.
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end })
        return try modelContext.fetch(descriptor).map { record in
            // Accounting reads refuse unknown stored values rather than guess a sign (see `ledgerLine()`).
            let line = try record.ledgerLine()
            return AnalyticsEntry(
                amount: line.amount, type: line.type, status: line.status, occurredAt: line.occurredAt,
                categoryID: record.categoryID, merchantID: record.merchantID, merchantName: record.merchantNameSnapshot)
        }
    }
}
