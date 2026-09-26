import Foundation
import HouseholdHubCore

/// Budget › Transactions filter bar state (spec §24.2: period, category, status).
struct TransactionFilter: Hashable {
    enum Period: String, CaseIterable, Identifiable {
        case all
        case thisWeek
        case thisMonth
        case last30Days

        var id: String { rawValue }
    }

    var period = Period.all
    var categoryID: UUID?
    var status: TransactionStatus?

    /// Earliest `occurredAt` included, in the household calendar.
    func startDate(now: Date, calendar: HouseholdCalendar) -> Date? {
        switch period {
        case .all: return nil
        case .thisWeek: return calendar.startOfWeek(for: now)
        case .thisMonth: return calendar.startOfMonth(for: now)
        case .last30Days: return calendar.calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now))
        }
    }

    var isActive: Bool { self != TransactionFilter() }
}
