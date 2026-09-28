import Foundation
import HouseholdHubCore
import SwiftData

/// Budget › Transactions filter bar state (spec §24.2: period, category, status; Sprint 10: account). Sprint 23
/// (F6): a date range and an amount range, and `Codable` so a saved search can keep it (a device setting).
struct TransactionFilter: Hashable, Codable {
    enum Period: String, CaseIterable, Identifiable, Codable {
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
    /// Sprint 23 (F6): only transactions dated in this interval (end excluded), within the period as well. Budget's
    /// custom dates set it from the first day's start to the day after the last; Analytics passes its report range.
    var dateRange: DateInterval?
    /// Sprint 23 (F6): the smallest and largest amount shown, in minor units of the household currency. An amount is
    /// a magnitude (`type` gives the sign), so the range reads the same for spending and income.
    var minimumAmountMinorUnits: Int64?
    var maximumAmountMinorUnits: Int64?

    enum CodingKeys: String, CodingKey {
        case period
        case categoryID
        case status
        case accountID
        case uncategorizedOnly
        case dateRange
        case minimumAmountMinorUnits
        case maximumAmountMinorUnits
    }

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
        let start = max(startDate(now: now, calendar: calendar) ?? .distantPast, dateRange?.start ?? .distantPast)
        let end = dateRange?.end ?? .distantFuture
        let minimumAmount = minimumAmountMinorUnits ?? Int64.min
        let maximumAmount = maximumAmountMinorUnits ?? Int64.max
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
                $0.occurredAt >= start && $0.occurredAt < end
                    && $0.amountMinorUnits >= minimumAmount && $0.amountMinorUnits <= maximumAmount
                    && (anyCategory || ($0.categoryID == wantedCategory && $0.typeRawValue != excludedType))
                    && (anyStatus || $0.statusRawValue == wantedStatus)
                    && (anyAccount || $0.accountID == wantedAccount || $0.transferAccountID == wantedAccount)
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
    }
}

extension TransactionFilter {
    /// Reads a saved filter leniently (Sprint 23, F6): a missing field, or a period this version doesn't know, reads as
    /// "no filter" for that field instead of losing the whole saved search. Declared here so the memberwise
    /// initializer stays.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let periodValue = try container.decodeIfPresent(String.self, forKey: .period) ?? ""
        let statusValue = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.init(
            period: Period(rawValue: periodValue) ?? .all,
            categoryID: try container.decodeIfPresent(UUID.self, forKey: .categoryID),
            status: TransactionStatus(rawValue: statusValue),
            accountID: try container.decodeIfPresent(UUID.self, forKey: .accountID),
            uncategorizedOnly: try container.decodeIfPresent(Bool.self, forKey: .uncategorizedOnly) ?? false,
            dateRange: try container.decodeIfPresent(DateInterval.self, forKey: .dateRange),
            minimumAmountMinorUnits: try container.decodeIfPresent(Int64.self, forKey: .minimumAmountMinorUnits),
            maximumAmountMinorUnits: try container.decodeIfPresent(Int64.self, forKey: .maximumAmountMinorUnits))
    }
}
