import Foundation

/// Where a date falls relative to "now", for UI labels. The app layer turns this into localized text.
public enum RelativeDay: Equatable, Sendable {
    case today
    case yesterday
    case tomorrow
    /// 2–6 days in the past; the associated value is `Calendar` weekday (1 = Sunday).
    case earlierThisWeek(weekday: Int)
    case other
}

/// Every calendar calculation goes through here (spec §10.3). Bounds are half-open: an "end" is the first instant
/// of the next period, so `start <= date < end` and DST days are handled by Foundation.
public struct HouseholdCalendar: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone, locale: Locale = .current, firstWeekday: Int? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        if let firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }

    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Exclusive end: the first instant of the following day.
    public func endOfDay(for date: Date) -> Date {
        interval(.day, containing: date).end
    }

    public func startOfWeek(for date: Date) -> Date {
        interval(.weekOfYear, containing: date).start
    }

    public func startOfMonth(for date: Date) -> Date {
        interval(.month, containing: date).start
    }

    /// Exclusive end: the first instant of the following month.
    public func endOfMonth(for date: Date) -> Date {
        interval(.month, containing: date).end
    }

    public func startOfYear(for date: Date) -> Date {
        interval(.year, containing: date).start
    }

    /// Whole calendar days from `from` to `to` (negative when `to` is earlier), ignoring time of day.
    public func dayDifference(from: Date, to: Date) -> Int {
        let components = calendar.dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to))
        return components.day ?? 0
    }

    public func relativeDay(for date: Date, now: Date) -> RelativeDay {
        switch dayDifference(from: now, to: date) {
        case 0: return .today
        case -1: return .yesterday
        case 1: return .tomorrow
        case (-6)...(-2): return .earlierThisWeek(weekday: calendar.component(.weekday, from: date))
        default: return .other
        }
    }

    private func interval(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
    }
}
