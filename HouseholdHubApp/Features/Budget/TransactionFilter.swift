import Foundation
import HouseholdHubCore
import SwiftData

/// Budget › Transactions filter bar state (spec §24.2: period, category, status; Sprint 10: account).
struct TransactionFilter: Hashable {
    enum Period: String, CaseIterable, Identifiable {
        case all
        case thisWeek
        case thisMonth
        case last30Days

        var id: String { rawValue }
    }

    /// The Category picker's choice: every category, only transactions without one, or one category.
    enum CategoryChoice: Hashable {
        case all
        case uncategorized
        case category(UUID)
    }

    var period = Period.all
    var categoryID: UUID?
    var status: TransactionStatus?
    /// Transactions in this account, including transfers into or out of it.
    var accountID: UUID?
    /// Sprint 23 (A-006): only transactions with no category. Transfers never have one and are left out.
    var uncategorizedOnly = false

    var categoryChoice: CategoryChoice {
        get {
            if uncategorizedOnly {
                return .uncategorized
            }
            if let categoryID {
                return .category(categoryID)
            }
            return .all
        }
        set {
            switch newValue {
            case .all:
                categoryID = nil
                uncategorizedOnly = false
            case .uncategorized:
                categoryID = nil
                uncategorizedOnly = true
            case .category(let id):
                categoryID = id
                uncategorizedOnly = false
            }
        }
    }

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

    /// The store query for this filter, newest first; the list narrows it further by search and pages it.
    func fetchDescriptor(now: Date, calendar: HouseholdCalendar) -> FetchDescriptor<TransactionRecord> {
        let start = startDate(now: now, calendar: calendar) ?? .distantPast
        // Uncategorized is "category is nil", excluding transfers; a chosen category never matches a transfer, so the
        // type check only bites for Uncategorized ("" is no type).
        let wantedCategory: UUID? = uncategorizedOnly ? nil : categoryID
        let anyCategory = categoryID == nil && !uncategorizedOnly
        let excludedType = uncategorizedOnly ? TransactionType.transfer.rawValue : ""
        let wantedStatus = status?.rawValue ?? ""
        let anyStatus = status == nil
        let wantedAccount: UUID? = accountID
        let anyAccount = accountID == nil
        return FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.occurredAt >= start
                    && (anyCategory || ($0.categoryID == wantedCategory && $0.typeRawValue != excludedType))
                    && (anyStatus || $0.statusRawValue == wantedStatus)
                    && (anyAccount || $0.accountID == wantedAccount || $0.transferAccountID == wantedAccount)
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
    }
}
