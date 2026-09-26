import Foundation
import SwiftData

/// What the Accounts editor sends (Sprint 10). The starting balance is signed: a credit card that owes 500 starts at
/// -500. The UI asks for "owed" on a card and negates it; the service stores what it is given.
public struct AccountDraft: Equatable, Sendable {
    public var name: String
    public var kind: AccountKind
    public var startingBalance: Money
    public var startingBalanceDate: Date

    public init(name: String, kind: AccountKind, startingBalance: Money, startingBalanceDate: Date) {
        self.name = name
        self.kind = kind
        self.startingBalance = startingBalance
        self.startingBalanceDate = startingBalanceDate
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Accounts (owner decision 13, Sprint 10). They live on the transaction service because they hold baselines and
/// every transaction references one: a single writer keeps "in use" checks and archiving race-free.
extension TransactionService {
    public static let mainAccountName = "Main account"

    /// Adds an account at the end of the list.
    @discardableResult
    public func createAccount(_ draft: AccountDraft, now: Date) throws -> UUID {
        begin()
        let settings = try requireSettings()
        try requireValid(draft, settings: settings, now: now)
        let last = try modelContext.fetch(FetchDescriptor<Account>()).map(\.sortOrder).max() ?? -1
        let account = Account(
            name: draft.trimmedName, kind: draft.kind, startingBalance: draft.startingBalance,
            startingBalanceDate: draft.startingBalanceDate, sortOrder: last + 1, now: now)
        modelContext.insert(account)
        try commit()
        return account.id
    }

    /// Renames, re-kinds, or corrects an account's baseline (§9.1: a baseline, so no transaction changes). An account
    /// a savings goal uses can't become a credit card.
    public func updateAccount(_ id: UUID, with draft: AccountDraft, now: Date) throws {
        begin()
        let settings = try requireSettings()
        try requireValid(draft, settings: settings, now: now)
        let account = try requireAccount(id)
        if draft.kind.isLiability, !account.kind.isLiability {
            let goals = try goalCount(usingAccount: id)
            guard goals == 0 else { throw GoalError.usedByGoals(count: goals) }
        }
        account.name = draft.trimmedName
        account.kind = draft.kind
        account.startingBalanceMinorUnits = draft.startingBalance.minorUnits
        account.startingBalanceDate = draft.startingBalanceDate
        account.updatedAt = now
        try commit()
    }

    /// Archived accounts keep their history and still count in the household total; they are no longer offered for
    /// new entries. The default account can't be archived.
    public func setAccountArchived(_ archived: Bool, account id: UUID, now: Date) throws {
        begin()
        let settings = try requireSettings()
        let account = try requireAccount(id)
        guard !(archived && settings.defaultAccountID == id) else { throw LedgerError.defaultAccountRequired }
        account.isArchived = archived
        account.updatedAt = now
        try commit()
    }

    /// Deletes an account nothing references (Sprint 10 decision 4); otherwise it is refused and the caller offers
    /// archiving. The default account can't be deleted, nor one a savings goal uses (Sprint 12 decision 6).
    public func deleteAccount(_ id: UUID) throws {
        begin()
        let settings = try requireSettings()
        let account = try requireAccount(id)
        guard settings.defaultAccountID != id else { throw LedgerError.defaultAccountRequired }
        let references = try accountReferenceCount(id)
        guard references == 0 else { throw LedgerError.accountInUse(referenceCount: references) }
        let goals = try goalCount(usingAccount: id)
        guard goals == 0 else { throw GoalError.usedByGoals(count: goals) }
        modelContext.delete(account)
        try commit()
    }

    public func setDefaultAccount(_ id: UUID, now: Date) throws {
        begin()
        let settings = try requireSettings()
        let account = try requireAccount(id)
        guard !account.isArchived else { throw LedgerError.archivedAccount }
        settings.defaultAccountID = id
        settings.updatedAt = now
        try commit()
    }

    /// Transactions (as source or destination) and recurring items that point at the account.
    public func accountReferenceCount(_ id: UUID) throws -> Int {
        let target: UUID? = id
        let records = try modelContext.fetchCount(
            FetchDescriptor<TransactionRecord>(
                predicate: #Predicate { $0.accountID == target || $0.transferAccountID == target }))
        let series = try modelContext.fetchCount(
            FetchDescriptor<RecurringTransaction>(
                predicate: #Predicate { $0.accountID == target || $0.transferAccountID == target }))
        return records + series
    }

    // MARK: Internals

    func insertMainAccount(currencyCode: String, now: Date) throws -> Account {
        let account = Account(
            name: Self.mainAccountName, kind: .bank, startingBalance: .zero(currencyCode), startingBalanceDate: now,
            sortOrder: 0, now: now)
        modelContext.insert(account)
        return account
    }

    func defaultAccount(_ settings: AppSettings) throws -> Account? {
        guard let id = settings.defaultAccountID else { return nil }
        return try account(id)
    }

    /// The default account, created as "Main account" if a store has none (a settings row from before accounts).
    func requireDefaultAccount(_ settings: AppSettings, now: Date) throws -> Account {
        if let existing = try defaultAccount(settings) {
            return existing
        }
        let main = try insertMainAccount(currencyCode: settings.currencyCode, now: now)
        settings.defaultAccountID = main.id
        return main
    }

    /// The account a new entry goes to: the one asked for (it must exist and be active), else the default.
    func resolveAccount(_ requested: UUID?, settings: AppSettings, now: Date) throws -> UUID {
        guard let requested else { return try requireDefaultAccount(settings, now: now).id }
        try requireUsableAccount(requested)
        return requested
    }

    /// An account a new or changed reference may point at: it exists and, unless it is the reference already
    /// stored, it is not archived (the same rule as categories).
    func requireUsableAccount(_ id: UUID, allowArchived: Bool = false) throws {
        let account = try requireAccount(id)
        guard allowArchived || !account.isArchived else { throw LedgerError.archivedAccount }
    }

    func requireAccount(_ id: UUID) throws -> Account {
        guard let account = try account(id) else { throw LedgerError.unknownAccount }
        return account
    }

    private func account(_ id: UUID) throws -> Account? {
        try modelContext.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first
    }

    private func requireValid(_ draft: AccountDraft, settings: AppSettings, now: Date) throws {
        guard !draft.trimmedName.isEmpty else { throw LedgerError.emptyAccountName }
        try requireCurrency(draft.startingBalance, settings)
        guard draft.startingBalanceDate <= now else { throw LedgerError.startingBalanceInFuture }
    }
}

extension TransactionService {
    /// A draft's source account (nil = the default) and a transfer's destination, checked: both exist, a newly
    /// chosen one is active, and a transfer's two accounts differ once the default is filled in. `current` holds the
    /// accounts a record already has, which may stay even if archived since.
    func resolveAccounts(
        _ draft: TransactionDraft, settings: AppSettings, current: (UUID?, UUID?)?, now: Date
    ) throws -> (source: UUID, destination: UUID?) {
        let source: UUID
        if let requested = draft.accountID {
            try requireUsableAccount(requested, allowArchived: requested == current?.0)
            source = requested
        } else if let kept = current?.0 {
            source = kept
        } else {
            source = try requireDefaultAccount(settings, now: now).id
        }
        guard draft.type == .transfer else { return (source, nil) }
        guard let destination = draft.transferAccountID, destination != source else {
            throw LedgerError.transferNeedsTwoAccounts
        }
        try requireUsableAccount(destination, allowArchived: destination == current?.1)
        return (source, destination)
    }
}
