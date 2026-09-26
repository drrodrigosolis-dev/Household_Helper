import Foundation
import SwiftData

/// Savings goals (owner decision 19, Sprint 12). They live on the transaction service because they point at accounts
/// and wishlist items: one writer keeps "a goal uses it" checks on deletes race-free.
extension TransactionService {
    /// Adds a goal at the end of the list, in the household currency, on an account that holds money.
    @discardableResult
    public func createGoal(_ draft: GoalDraft, now: Date) throws -> UUID {
        begin()
        try requireValid(draft, goalID: nil)
        let last = try modelContext.fetch(FetchDescriptor<SavingsGoal>()).map(\.sortOrder).max() ?? -1
        let goal = SavingsGoal(
            name: draft.trimmedName, target: draft.target, accountID: draft.accountID, targetDate: draft.targetDate,
            wishlistItemID: draft.wishlistItemID, sortOrder: last + 1, now: now)
        modelContext.insert(goal)
        try commit()
        return goal.id
    }

    public func updateGoal(_ id: UUID, with draft: GoalDraft, now: Date) throws {
        begin()
        let goal = try requireGoal(id)
        try requireValid(draft, goalID: id)
        goal.name = draft.trimmedName
        goal.targetMinorUnits = draft.target.minorUnits
        goal.currencyCode = draft.target.currencyCode
        goal.accountID = draft.accountID
        goal.targetDate = draft.targetDate
        goal.wishlistItemID = draft.wishlistItemID
        goal.updatedAt = now
        try commit()
    }

    /// A reached goal stays on show until archived (Sprint 12 decision 4). Archived goals still hold their account and
    /// wishlist item.
    public func setGoalArchived(_ archived: Bool, goal id: UUID, now: Date) throws {
        begin()
        let goal = try requireGoal(id)
        goal.isArchived = archived
        goal.updatedAt = now
        try commit()
    }

    /// Deletes the goal only; its account and wishlist item are untouched.
    public func deleteGoal(_ id: UUID) throws {
        begin()
        modelContext.delete(try requireGoal(id))
        try commit()
    }

    /// Every goal's figures today, archived ones last, each group in list order.
    public func goalReport(now: Date, calendar: HouseholdCalendar) throws -> [GoalStatus] {
        let goals = try modelContext.fetch(FetchDescriptor<SavingsGoal>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard !goals.isEmpty else { return [] }
        let settings = try requireSettings()
        let all = try balances(
            now: now, calendar: calendar, includePendingInProjection: settings.includePendingInProjection)
        let calculator = GoalCalculator()
        let statuses = try goals.map { goal -> GoalStatus in
            guard let balance = all.balance(of: goal.accountID) else {
                throw LedgerError.unreadableRecord(field: "SavingsGoal.accountID", value: goal.accountID.uuidString)
            }
            return try calculator.status(of: goal.rule, saved: balance.current, now: now, calendar: calendar)
        }
        return statuses.filter { !$0.rule.isArchived } + statuses.filter(\.rule.isArchived)
    }

    /// Goals (archived included) that use the account.
    public func goalCount(usingAccount id: UUID) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.accountID == id }))
    }

    /// Goals (archived included) that use the wishlist item: at most one.
    public func goalCount(usingWishlistItem id: UUID) throws -> Int {
        let target: UUID? = id
        return try modelContext.fetchCount(
            FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.wishlistItemID == target }))
    }

    // MARK: Internals

    func requireGoal(_ id: UUID) throws -> SavingsGoal {
        let descriptor = FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.id == id })
        guard let goal = try modelContext.fetch(descriptor).first else { throw GoalError.unknownGoal }
        return goal
    }

    private func requireValid(_ draft: GoalDraft, goalID: UUID?) throws {
        guard !draft.trimmedName.isEmpty else { throw GoalError.emptyName }
        guard draft.target.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        try requireCurrency(draft.target, try requireSettings())
        let account = try requireAccount(draft.accountID)
        guard !account.kind.isLiability else { throw GoalError.liabilityAccount }
        guard let itemID = draft.wishlistItemID else { return }
        let item = try requireWishlistItem(itemID)
        guard item.currencyCode == draft.target.currencyCode else {
            throw LedgerError.currencyMismatch(expected: draft.target.currencyCode, actual: item.currencyCode)
        }
        let target: UUID? = itemID
        let others = try modelContext.fetch(
            FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.wishlistItemID == target }))
        guard others.allSatisfy({ $0.id == goalID }) else { throw GoalError.wishlistItemHasGoal }
    }
}
