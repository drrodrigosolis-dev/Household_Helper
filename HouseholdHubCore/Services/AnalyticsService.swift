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
        var settingsDescriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        guard let settings = try modelContext.fetch(settingsDescriptor).first else { throw LedgerError.settingsMissing }
        let interval = period.interval(now: now, calendar: calendar)
        let start = interval.start
        let end = interval.end
        let posted = TransactionStatus.posted.rawValue
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end && $0.statusRawValue == posted })
        let entries = try modelContext.fetch(descriptor).map { record in
            // Accounting reads refuse unknown stored values rather than guess a sign (see `ledgerLine()`).
            let line = try record.ledgerLine()
            return AnalyticsEntry(
                amount: line.amount, type: line.type, status: line.status, occurredAt: line.occurredAt,
                categoryID: record.categoryID, merchantID: record.merchantID, merchantName: record.merchantNameSnapshot)
        }
        return try AnalyticsEngine().report(
            entries, period: period, now: now, calendar: calendar, currencyCode: settings.currencyCode)
    }
}
