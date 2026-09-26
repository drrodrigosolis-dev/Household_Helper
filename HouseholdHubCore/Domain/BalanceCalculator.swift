import Foundation

/// The three balance concepts from spec §9.2. They are never all called "balance" in the UI.
public struct BalanceSnapshot: Equatable, Sendable {
    /// Starting balance plus posted transactions up to now.
    public let current: Money
    /// Net effect of pending (not cancelled, not yet posted) transactions.
    public let pendingImpact: Money
    /// Current, plus future-dated posted items and unmaterialized recurring occurrences in the window, plus pending
    /// when requested.
    public let projected: Money
    /// `[now, now + projectionDays)` in calendar days.
    public let projectionWindow: DateInterval
}

/// One account's figures (Sprint 10). The same three §9 concepts, signed: a credit card's current is normally
/// negative, the amount owed.
public struct AccountBalance: Equatable, Sendable {
    public let accountID: UUID
    public let snapshot: BalanceSnapshot

    public init(accountID: UUID, snapshot: BalanceSnapshot) {
        self.accountID = accountID
        self.snapshot = snapshot
    }
}

/// Every account's figures and the household's, which are their sums (Sprint 10 decisions 1 and 5: transfers move
/// money between accounts and leave the household figures unchanged).
public struct HouseholdBalances: Equatable, Sendable {
    public let accounts: [AccountBalance]
    public let household: BalanceSnapshot

    public func balance(of accountID: UUID) -> BalanceSnapshot? {
        accounts.first { $0.accountID == accountID }?.snapshot
    }
}

/// Deterministic balance math over value snapshots (spec §9). No persistence, no clock, no AI.
public struct BalanceCalculator: Sendable {
    public let projectionDays: Int
    private let engine = RecurrenceEngine()

    public init(projectionDays: Int = 30) {
        self.projectionDays = projectionDays
    }

    /// - Parameters:
    ///   - lines: every transaction the store holds after `startingBalanceDate` (cancelled ones included, so their
    ///     recurring occurrences are known to be handled).
    ///   - includePendingInProjection: the user's choice from spec §9.3.
    public func snapshot(
        startingBalance: Money, startingBalanceDate: Date, lines: [LedgerLine], series: [RecurringSeries], now: Date,
        calendar: HouseholdCalendar, includePendingInProjection: Bool
    ) throws -> BalanceSnapshot {
        // One household balance is one account holding every line: the same code path as `balances`, so the §9
        // tests written against this entry point cover what the app runs. A transfer names the account as both
        // source and destination, which makes it neutral, as it is to a single balance.
        let only = AccountBaseline(
            id: UUID(), kind: .bank, startingBalance: startingBalance, startingBalanceDate: startingBalanceDate)
        let placed = lines.map { line in
            var copy = line
            copy.accountID = only.id
            copy.transferAccountID = line.type == .transfer ? only.id : nil
            return copy
        }
        let placedSeries = series.map { item in
            var copy = item
            copy.accountID = only.id
            copy.transferAccountID = item.type == .transfer ? only.id : nil
            return copy
        }
        return try balances(
            accounts: [only], lines: placed, series: placedSeries, now: now, calendar: calendar,
            includePendingInProjection: includePendingInProjection, currencyCode: startingBalance.currencyCode
        ).household
    }

    /// Per-account figures and the household's (Sprint 10). Each account counts the lines after its own starting
    /// date; a recurring occurrence already materialized by any record (whichever account it went to) is not
    /// projected again, so moving a series to another account cannot double-count a handled occurrence.
    /// - Parameters:
    ///   - lines: every transaction record, cancelled ones included.
    ///   - currencyCode: the household currency, for the sums when there are no accounts.
    public func balances(
        accounts: [AccountBaseline], lines: [LedgerLine], series: [RecurringSeries], now: Date,
        calendar: HouseholdCalendar, includePendingInProjection: Bool, currencyCode: String
    ) throws -> HouseholdBalances {
        let end = calendar.calendar.date(byAdding: .day, value: projectionDays, to: now) ?? now
        let window = DateInterval(start: now, end: max(end, now))
        var materialized = Set<OccurrenceKey>()
        for line in lines {
            if let id = line.recurringSeriesID, let occurrence = line.scheduledOccurrence {
                materialized.insert(OccurrenceKey(seriesID: id, occurrence: occurrence))
            }
        }
        // One entry per occurrence still to come, so a series due twice in the window counts twice.
        var dueOccurrences: [RecurringSeries] = []
        for item in series {
            for occurrence in engine.occurrences(of: item, in: window) {
                if !materialized.contains(OccurrenceKey(seriesID: item.id, occurrence: occurrence)) {
                    dueOccurrences.append(item)
                }
            }
        }
        // Every line must name accounts this household has; a line that names none would silently leave every
        // figure, so it is refused like any unreadable record.
        let known = Set(accounts.map(\.id))
        for line in lines {
            guard let source = line.accountID, known.contains(source) else {
                throw LedgerError.unreadableRecord(field: "accountID", value: line.accountID?.uuidString ?? "none")
            }
            if let destination = line.transferAccountID, !known.contains(destination) {
                throw LedgerError.unreadableRecord(field: "transferAccountID", value: destination.uuidString)
            }
        }
        for item in series {
            guard let source = item.accountID, known.contains(source) else {
                throw LedgerError.unreadableRecord(field: "accountID", value: item.accountID?.uuidString ?? "none")
            }
            if let destination = item.transferAccountID, !known.contains(destination) {
                throw LedgerError.unreadableRecord(field: "transferAccountID", value: destination.uuidString)
            }
        }
        let live = lines.filter { $0.status != .cancelled }
        var results: [AccountBalance] = []
        for account in accounts {
            let code = account.startingBalance.currencyCode
            let counted = live.filter { $0.occurredAt > account.startingBalanceDate }
            func sum(_ selected: [LedgerLine]) throws -> Money {
                try Money.sum(selected.map { try $0.effect(onAccount: account.id) }, currencyCode: code)
            }
            let current = try account.startingBalance.adding(
                sum(counted.filter { $0.status == .posted && $0.occurredAt <= now }))
            let pendingImpact = try sum(counted.filter { $0.status == .pending })
            let upcoming = counted.filter { $0.status == .posted && $0.occurredAt > now && $0.occurredAt < window.end }
            let future = try sum(upcoming)
            let recurring = try Money.sum(
                dueOccurrences.map { try $0.effect(onAccount: account.id) }, currencyCode: code)
            var projected = try current.adding(future).adding(recurring)
            if includePendingInProjection {
                projected = try projected.adding(pendingImpact)
            }
            let snapshot = BalanceSnapshot(
                current: current, pendingImpact: pendingImpact, projected: projected, projectionWindow: window)
            results.append(AccountBalance(accountID: account.id, snapshot: snapshot))
        }
        let snapshots = results.map(\.snapshot)
        let household = BalanceSnapshot(
            current: try Money.sum(snapshots.map(\.current), currencyCode: currencyCode),
            pendingImpact: try Money.sum(snapshots.map(\.pendingImpact), currencyCode: currencyCode),
            projected: try Money.sum(snapshots.map(\.projected), currencyCode: currencyCode), projectionWindow: window)
        return HouseholdBalances(accounts: results, household: household)
    }
}

private struct OccurrenceKey: Hashable {
    let seriesID: UUID
    let occurrence: Date
}
