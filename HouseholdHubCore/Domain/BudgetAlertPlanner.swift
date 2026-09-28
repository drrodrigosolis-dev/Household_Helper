import Foundation

/// The share of a budget that triggers an alert (Sprint 23 F7).
public enum BudgetAlertThreshold: Int, CaseIterable, Comparable, Sendable {
    case eighty = 80
    case hundred = 100

    public static func < (lhs: BudgetAlertThreshold, rhs: BudgetAlertThreshold) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One budget this month, as the alert planner needs it: `spent` and `available` from `BudgetStatus` (refunds already
/// netted, so a refund brings spending back down).
public struct BudgetAlertSource: Equatable, Sendable {
    public var categoryID: UUID
    public var categoryName: String
    public var spent: Money
    public var available: Money

    public init(categoryID: UUID, categoryName: String, spent: Money, available: Money) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.spent = spent
        self.available = available
    }

    public init(_ status: BudgetStatus, categoryName: String) {
        self.init(
            categoryID: status.categoryID, categoryName: categoryName, spent: status.spent,
            available: status.available)
    }
}

/// An alert to deliver now. The app words it with the category name only, never an amount (Lock Screen privacy).
public struct PlannedBudgetAlert: Equatable, Sendable, Identifiable {
    /// The notification identifier; also the "already sent" key.
    public let id: String
    public let categoryID: UUID
    public let categoryName: String
    public let threshold: BudgetAlertThreshold
}

public struct BudgetAlertPlan: Equatable, Sendable {
    public let alerts: [PlannedBudgetAlert]
    /// What to remember as sent: this month's keys only, so a new month starts afresh.
    public let sentKeys: [String]
}

/// Decides which budget alerts are due (Sprint 23 F7). Pure: the app passes this month's budgets and the keys it
/// stored as sent. Each threshold fires once per category per month. A budget that jumps past both thresholds at once
/// gets only the 100 % alert, and the 80 % one is marked sent too, so it never arrives late. Falling back under a
/// threshold (a refund) sends nothing, and crossing it again the same month does not repeat the alert.
public struct BudgetAlertPlanner: Sendable {
    public init() {}

    public func plan(_ sources: [BudgetAlertSource], month: BudgetMonth, alreadySent: Set<String>) -> BudgetAlertPlan {
        let prefix = Self.monthPrefix(month)
        var sent = alreadySent.filter { $0.hasPrefix(prefix) }
        var alerts: [PlannedBudgetAlert] = []
        let ordered = sources.sorted {
            ($0.categoryName, $0.categoryID.uuidString) < ($1.categoryName, $1.categoryID.uuidString)
        }
        for source in ordered {
            guard let reached = Self.reached(spent: source.spent, available: source.available) else { continue }
            let due = BudgetAlertThreshold.allCases.filter {
                $0 <= reached && !sent.contains(Self.key(month: month, categoryID: source.categoryID, threshold: $0))
            }
            guard let highest = due.max() else { continue }
            for threshold in due {
                sent.insert(Self.key(month: month, categoryID: source.categoryID, threshold: threshold))
            }
            alerts.append(
                PlannedBudgetAlert(
                    id: Self.key(month: month, categoryID: source.categoryID, threshold: highest),
                    categoryID: source.categoryID, categoryName: source.categoryName, threshold: highest))
        }
        return BudgetAlertPlan(alerts: alerts, sentKeys: sent.sorted())
    }

    /// "budget-2026-9-<category>-80".
    public static func key(month: BudgetMonth, categoryID: UUID, threshold: BudgetAlertThreshold) -> String {
        monthPrefix(month) + "\(categoryID.uuidString)-\(threshold.rawValue)"
    }

    static func monthPrefix(_ month: BudgetMonth) -> String {
        "budget-\(month.year)-\(month.month)-"
    }

    /// The highest threshold `spent` has reached, in integer minor units. Nothing spent reaches nothing; with nothing
    /// available (a rollover overspend) any spending is over.
    public static func reached(spent: Money, available: Money) -> BudgetAlertThreshold? {
        guard spent.currencyCode == available.currencyCode, spent.minorUnits > 0 else { return nil }
        guard available.minorUnits > 0, spent.minorUnits < available.minorUnits else { return .hundred }
        // spent / available >= 4/5, cross-multiplied; both are below Int64.max / 5 for any amount the app accepts.
        let (spentFive, spentOverflow) = spent.minorUnits.multipliedReportingOverflow(by: 5)
        let (availableFour, availableOverflow) = available.minorUnits.multipliedReportingOverflow(by: 4)
        if spentOverflow || availableOverflow {
            return spent.minorUnits / 4 >= available.minorUnits / 5 ? .eighty : nil
        }
        return spentFive >= availableFour ? .eighty : nil
    }
}
