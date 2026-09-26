import Foundation

public enum GoalError: Error, Equatable, Sendable {
    case unknownGoal
    case emptyName
    /// Progress is an account's balance, so it has to be an account that holds money, not a credit card.
    case liabilityAccount
    /// A wishlist item has at most one goal.
    case wishlistItemHasGoal
    /// Goals still use the account or wishlist item; delete or change them first (Sprint 12 decision 6).
    case usedByGoals(count: Int)
}

/// What the goal editor sends (Sprint 12).
public struct GoalDraft: Equatable, Sendable {
    public var name: String
    public var target: Money
    public var accountID: UUID
    public var targetDate: Date?
    public var wishlistItemID: UUID?

    public init(name: String, target: Money, accountID: UUID, targetDate: Date? = nil, wishlistItemID: UUID? = nil) {
        self.name = name
        self.target = target
        self.accountID = accountID
        self.targetDate = targetDate
        self.wishlistItemID = wishlistItemID
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A goal as value data for the math.
public struct GoalRule: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var target: Money
    public var accountID: UUID
    public var targetDate: Date?
    public var wishlistItemID: UUID?
    public var isArchived: Bool

    public init(
        id: UUID, name: String, target: Money, accountID: UUID, targetDate: Date?, wishlistItemID: UUID?,
        isArchived: Bool
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.accountID = accountID
        self.targetDate = targetDate
        self.wishlistItemID = wishlistItemID
        self.isArchived = isArchived
    }
}

/// One goal's figures on one day (Sprint 12 decisions 2–4).
public struct GoalStatus: Equatable, Sendable, Identifiable {
    public let rule: GoalRule
    /// The account's current (posted) balance; it can be below zero.
    public let saved: Money
    /// What is still missing, never below zero.
    public let remaining: Money
    /// Whole months from today to the target date, at least 1; nil without a date or once the date has passed.
    public let monthsLeft: Int?
    /// `remaining` spread over `monthsLeft`, rounded up to the currency's minor unit; nil without a date. Once the
    /// date has passed it is the whole of `remaining`.
    public let neededPerMonth: Money?
    /// The target date has passed and the goal isn't reached.
    public let isOverdue: Bool

    public var id: UUID { rule.id }
    public var isReached: Bool { remaining.isZero }

    /// Saved as a share of the target, 0...1, for progress bars only (a ratio, never money).
    public var progressFraction: Double {
        guard rule.target.minorUnits > 0, saved.minorUnits > 0 else { return 0 }
        return min(1, Double(saved.minorUnits) / Double(rule.target.minorUnits))
    }
}

/// Deterministic savings-goal math (Sprint 12). No persistence, no clock; days and months go through
/// `HouseholdCalendar`.
public struct GoalCalculator: Sendable {
    public init() {}

    /// - Parameter saved: the goal account's current balance, in the goal's currency.
    public func status(of rule: GoalRule, saved: Money, now: Date, calendar: HouseholdCalendar) throws -> GoalStatus {
        let missing = try rule.target.subtracting(saved)
        let remaining = missing.minorUnits > 0 ? missing : .zero(rule.target.currencyCode)
        guard let targetDate = rule.targetDate else {
            return GoalStatus(
                rule: rule, saved: saved, remaining: remaining, monthsLeft: nil, neededPerMonth: nil, isOverdue: false)
        }
        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: targetDate)
        guard targetDay >= today else {
            return GoalStatus(
                rule: rule, saved: saved, remaining: remaining, monthsLeft: nil, neededPerMonth: remaining,
                isOverdue: !remaining.isZero)
        }
        let whole = calendar.calendar.dateComponents([.month], from: today, to: targetDay).month ?? 0
        let months = max(1, whole)
        return GoalStatus(
            rule: rule, saved: saved, remaining: remaining, monthsLeft: months,
            neededPerMonth: Self.dividedRoundingUp(remaining, by: months), isOverdue: false)
    }

    /// `money` split into `parts` equal amounts, rounded up to the minor unit, so paying it every month reaches the
    /// total on time. `money` is never negative here and `parts` is at least 1, so this can't overflow.
    static func dividedRoundingUp(_ money: Money, by parts: Int) -> Money {
        let divisor = Int64(parts)
        let (quotient, remainder) = money.minorUnits.quotientAndRemainder(dividingBy: divisor)
        return Money(minorUnits: remainder > 0 ? quotient + 1 : quotient, currencyCode: money.currencyCode)
    }
}
