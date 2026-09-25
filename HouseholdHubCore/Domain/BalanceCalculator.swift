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
        let code = startingBalance.currencyCode
        let end = calendar.calendar.date(byAdding: .day, value: projectionDays, to: now) ?? now
        let window = DateInterval(start: now, end: max(end, now))
        let counted = lines.filter { $0.occurredAt > startingBalanceDate && $0.status != .cancelled }

        let postedToDate = counted.filter { $0.status == .posted && $0.occurredAt <= now }
        let current = try startingBalance.adding(net(postedToDate, code))

        let pendingImpact = try net(counted.filter { $0.status == .pending }, code)

        let futurePosted = counted.filter { $0.status == .posted && $0.occurredAt > now && $0.occurredAt < window.end }
        let futureEffect = try net(futurePosted, code)

        let recurringEffect = try projectedRecurring(series, lines: lines, window: window, currencyCode: code)

        var projected = try current.adding(futureEffect).adding(recurringEffect)
        if includePendingInProjection {
            projected = try projected.adding(pendingImpact)
        }
        return BalanceSnapshot(
            current: current, pendingImpact: pendingImpact, projected: projected, projectionWindow: window)
    }

    /// Sum of recurring occurrences in the window that no transaction record has materialized yet (any status:
    /// a cancelled materialization means the user skipped that occurrence).
    private func projectedRecurring(
        _ series: [RecurringSeries], lines: [LedgerLine], window: DateInterval, currencyCode: String
    ) throws -> Money {
        var materialized = Set<OccurrenceKey>()
        for line in lines {
            if let id = line.recurringSeriesID, let occurrence = line.scheduledOccurrence {
                materialized.insert(OccurrenceKey(seriesID: id, occurrence: occurrence))
            }
        }
        var total = Money.zero(currencyCode)
        let start = window.start
        for item in series {
            let template = LedgerLine(amount: item.templateAmount, type: item.type, status: .posted, occurredAt: start)
            let effect = try template.balanceEffect()
            for occurrence in engine.occurrences(of: item, in: window) {
                let key = OccurrenceKey(seriesID: item.id, occurrence: occurrence)
                if !materialized.contains(key) {
                    total = try total.adding(effect)
                }
            }
        }
        return total
    }

    private func net(_ lines: [LedgerLine], _ currencyCode: String) throws -> Money {
        try Money.sum(lines.map { try $0.balanceEffect() }, currencyCode: currencyCode)
    }
}

private struct OccurrenceKey: Hashable {
    let seriesID: UUID
    let occurrence: Date
}
