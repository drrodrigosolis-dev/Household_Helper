import Foundation

/// A recurring occurrence due soon that has not been recorded yet.
public struct UpcomingOccurrence: Equatable, Sendable, Identifiable {
    public let seriesID: UUID
    public let date: Date
    public let amount: Money
    public let type: TransactionType
    public let title: String?

    public var id: String { "\(seriesID.uuidString)-\(date.timeIntervalSinceReferenceDate)" }

    public init(seriesID: UUID, date: Date, amount: Money, type: TransactionType, title: String?) {
        self.seriesID = seriesID
        self.date = date
        self.amount = amount
        self.type = type
        self.title = title
    }
}

/// Everything the Dashboard shows besides recent activity (spec §24.2).
public struct DashboardSummary: Equatable, Sendable {
    public let balance: BalanceSnapshot
    /// Posted expenses since the start of this week, as a positive magnitude.
    public let spentThisWeek: Money
    /// Unrecorded recurring occurrences from the start of today through the next 7 days, soonest first.
    public let upcoming: [UpcomingOccurrence]

    public init(balance: BalanceSnapshot, spentThisWeek: Money, upcoming: [UpcomingOccurrence]) {
        self.balance = balance
        self.spentThisWeek = spentThisWeek
        self.upcoming = upcoming
    }
}
