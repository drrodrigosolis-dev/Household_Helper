import Foundation

public enum RecurrenceRuleError: Error, Equatable, Sendable {
    case invalid(String)
}

/// Strongly typed recurrence definition (spec §7.6). Weekdays use `Calendar` numbering: 1 = Sunday … 7 = Saturday.
public enum RecurrenceRule: Codable, Hashable, Sendable {
    /// Every `interval` weeks on `weekday`.
    case weekly(interval: Int, weekday: Int)
    /// On `day` of each month; months without that day use their last day (31 → Feb 28/29).
    case monthlyOnDay(day: Int)
    /// On the `ordinal`-th `weekday` of each month; `ordinal` is 1…4, or -1 for the last one.
    case monthlyOnWeekday(ordinal: Int, weekday: Int)
    /// Every year on `month`/`day`; Feb 29 falls on Feb 28 in non-leap years.
    case yearly(month: Int, day: Int)

    public func validate() throws {
        switch self {
        case .weekly(let interval, let weekday):
            try Self.require((1...52).contains(interval), "weekly interval must be 1...52")
            try Self.require((1...7).contains(weekday), "weekday must be 1...7")
        case .monthlyOnDay(let day):
            try Self.require((1...31).contains(day), "day of month must be 1...31")
        case .monthlyOnWeekday(let ordinal, let weekday):
            try Self.require([1, 2, 3, 4, -1].contains(ordinal), "ordinal must be 1...4 or -1 (last)")
            try Self.require((1...7).contains(weekday), "weekday must be 1...7")
        case .yearly(let month, let day):
            try Self.require((1...12).contains(month), "month must be 1...12")
            let maxDay = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
            try Self.require((1...maxDay).contains(day), "day \(day) does not exist in month \(month)")
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw RecurrenceRuleError.invalid(message) }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> RecurrenceRule {
        try JSONDecoder().decode(RecurrenceRule.self, from: data)
    }
}
