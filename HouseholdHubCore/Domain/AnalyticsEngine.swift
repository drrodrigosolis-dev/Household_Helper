import Foundation

/// The Analytics periods (Sprint 5 default 1): whole calendar months in the household calendar.
public enum AnalyticsPeriod: String, Codable, Sendable, CaseIterable {
    case thisMonth
    case lastMonth
    case last3Months
    case thisYear
    case last12Months

    /// The half-open interval `[start, end)` this period covers, relative to `now`.
    public func interval(now: Date, calendar: HouseholdCalendar) -> DateInterval {
        let monthStart = calendar.startOfMonth(for: now)
        let nextMonth = calendar.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
        func monthsBack(_ count: Int) -> Date {
            calendar.calendar.date(byAdding: .month, value: -count, to: monthStart) ?? monthStart
        }
        switch self {
        case .thisMonth: return DateInterval(start: monthStart, end: nextMonth)
        case .lastMonth: return DateInterval(start: monthsBack(1), end: monthStart)
        case .last3Months: return DateInterval(start: monthsBack(2), end: nextMonth)
        case .thisYear: return DateInterval(start: calendar.startOfYear(for: now), end: nextMonth)
        case .last12Months: return DateInterval(start: monthsBack(11), end: nextMonth)
        }
    }

    /// Trend bars group by week for single-month periods, by month otherwise.
    public var bucket: AnalyticsBucket {
        switch self {
        case .thisMonth, .lastMonth: return .week
        case .last3Months, .thisYear, .last12Months: return .month
        }
    }
}

public enum AnalyticsBucket: Sendable {
    case week
    case month
}

/// One transaction as analytics sees it.
public struct AnalyticsEntry: Sendable, Hashable {
    public var amount: Money
    public var type: TransactionType
    public var status: TransactionStatus
    public var occurredAt: Date
    public var categoryID: UUID?
    public var merchantID: UUID?
    public var merchantName: String?

    public init(
        amount: Money, type: TransactionType, status: TransactionStatus, occurredAt: Date, categoryID: UUID? = nil,
        merchantID: UUID? = nil, merchantName: String? = nil
    ) {
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.merchantID = merchantID
        self.merchantName = merchantName
    }
}

public struct CategorySpend: Sendable, Hashable, Identifiable {
    /// Nil is the "Uncategorized" bucket.
    public let categoryID: UUID?
    public let total: Money
    /// Share of all expenses in the period, 0...1 (display only; totals stay in minor units).
    public let share: Double

    public var id: String { categoryID?.uuidString ?? "uncategorized" }
}

public struct TrendPoint: Sendable, Hashable, Identifiable {
    /// Start of the week or month.
    public let start: Date
    public let income: Money
    public let expense: Money

    public var id: Date { start }
}

public struct MerchantSpend: Sendable, Hashable, Identifiable {
    public let key: String
    public let name: String
    public let total: Money
    public let count: Int

    public var id: String { key }
}

public struct AnalyticsReport: Sendable, Hashable {
    public let interval: DateInterval
    public let income: Money
    public let expense: Money
    /// Income minus expense; negative when the household spent more than it earned.
    public let net: Money
    public let byCategory: [CategorySpend]
    public let trend: [TrendPoint]
    public let topMerchants: [MerchantSpend]
}

/// Deterministic analytics (spec §2): posted income and expenses only (Sprint 5 default 2), in integer minor units.
public struct AnalyticsEngine: Sendable {
    public var merchantLimit = 5

    public init() {}

    public func report(
        _ entries: [AnalyticsEntry], period: AnalyticsPeriod, now: Date, calendar: HouseholdCalendar,
        currencyCode: String
    ) throws -> AnalyticsReport {
        let interval = period.interval(now: now, calendar: calendar)
        let counted = entries.filter {
            $0.status == .posted && $0.type != .transfer && $0.occurredAt >= interval.start
                && $0.occurredAt < interval.end
        }
        for entry in counted where entry.amount.currencyCode != currencyCode {
            throw LedgerError.currencyMismatch(expected: currencyCode, actual: entry.amount.currencyCode)
        }
        let incomes = counted.filter { $0.type == .income }
        let expenses = counted.filter { $0.type == .expense }
        let income = try Money.sum(incomes.map(\.amount), currencyCode: currencyCode)
        let expense = try Money.sum(expenses.map(\.amount), currencyCode: currencyCode)
        let spent = try expense.negated()
        let net = try income.adding(spent)
        let byCategory = try categories(expenses, total: expense, currencyCode: currencyCode)
        let points = try trend(
            counted, interval: interval, bucket: period.bucket, calendar: calendar, currencyCode: currencyCode)
        let top = try merchants(expenses, currencyCode: currencyCode)
        return AnalyticsReport(
            interval: interval, income: income, expense: expense, net: net, byCategory: byCategory, trend: points,
            topMerchants: top)
    }

    private func categories(
        _ expenses: [AnalyticsEntry], total: Money, currencyCode: String
    ) throws -> [CategorySpend] {
        let groups = Dictionary(grouping: expenses, by: \.categoryID)
        return try groups.map { categoryID, entries in
            let sum = try Money.sum(entries.map(\.amount), currencyCode: currencyCode)
            let share = total.minorUnits > 0 ? Double(sum.minorUnits) / Double(total.minorUnits) : 0
            return CategorySpend(categoryID: categoryID, total: sum, share: share)
        }
        .sorted { lhs, rhs in
            // Largest first; ties in a stable order so the chart and table never reshuffle.
            if lhs.total.minorUnits != rhs.total.minorUnits { return lhs.total.minorUnits > rhs.total.minorUnits }
            return lhs.id < rhs.id
        }
    }

    private func trend(
        _ entries: [AnalyticsEntry], interval: DateInterval, bucket: AnalyticsBucket, calendar: HouseholdCalendar,
        currencyCode: String
    ) throws -> [TrendPoint] {
        func bucketStart(_ date: Date) -> Date {
            switch bucket {
            case .week: return calendar.startOfWeek(for: date)
            case .month: return calendar.startOfMonth(for: date)
            }
        }
        // Every bucket in the interval appears, empty ones included, so the chart's axis is continuous.
        var starts: [Date] = []
        var cursor = bucketStart(interval.start)
        while cursor < interval.end {
            starts.append(cursor)
            let component: Calendar.Component = bucket == .week ? .weekOfYear : .month
            guard let next = calendar.calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        let groups = Dictionary(grouping: entries) { bucketStart($0.occurredAt) }
        return try starts.map { start in
            let entries = groups[start] ?? []
            let incomes = entries.filter { $0.type == .income }.map(\.amount)
            let expenses = entries.filter { $0.type == .expense }.map(\.amount)
            let income = try Money.sum(incomes, currencyCode: currencyCode)
            let expense = try Money.sum(expenses, currencyCode: currencyCode)
            return TrendPoint(start: start, income: income, expense: expense)
        }
    }

    private func merchants(_ expenses: [AnalyticsEntry], currencyCode: String) throws -> [MerchantSpend] {
        let named = expenses.filter { $0.merchantID != nil || !($0.merchantName ?? "").isEmpty }
        let groups = Dictionary(grouping: named) { entry in
            entry.merchantID?.uuidString ?? Merchant.normalize(entry.merchantName ?? "")
        }
        let totals = try groups.map { key, entries in
            // The name as last entered represents the merchant.
            let latest = entries.max { $0.occurredAt < $1.occurredAt }
            let sum = try Money.sum(entries.map(\.amount), currencyCode: currencyCode)
            return MerchantSpend(key: key, name: latest?.merchantName ?? "", total: sum, count: entries.count)
        }
        let sorted = totals.sorted { lhs, rhs in
            if lhs.total.minorUnits != rhs.total.minorUnits { return lhs.total.minorUnits > rhs.total.minorUnits }
            return lhs.key < rhs.key
        }
        return Array(sorted.prefix(merchantLimit))
    }
}
