import Foundation

/// Pure occurrence generator (spec §9.4): rule → bounded date range → dates. Nothing is persisted here.
///
/// Every occurrence keeps the series start's local time of day in the series' time zone, so a 09:00 bill stays at
/// 09:00 across DST changes. A local time skipped by a DST jump resolves to the next valid instant that day.
public struct RecurrenceEngine: Sendable {
    /// Hard stop against runaway loops; far above any realistic window.
    public static let maximumOccurrencesPerQuery = 5_000

    public init() {}

    /// Occurrences with `window.start <= date < window.end`, on or after `series.startDate` and on or before
    /// `series.endDate` (inclusive). Disabled series have none.
    public func occurrences(of series: RecurringSeries, in window: DateInterval) -> [Date] {
        guard series.isEnabled else { return [] }
        let calendar = HouseholdCalendar(timeZone: series.timeZone)
        let end = series.endDate
        return occurrences(of: series.rule, start: series.startDate, end: end, in: window, calendar: calendar)
    }

    public func occurrences(
        of rule: RecurrenceRule, start: Date, end: Date?, in window: DateInterval, calendar: HouseholdCalendar
    ) -> [Date] {
        guard (try? rule.validate()) != nil else { return [] }
        let generator = Generator(rule: rule, start: start, calendar: calendar)
        var results: [Date] = []
        var index = generator.firstUsefulIndex(for: window.start)
        while results.count < Self.maximumOccurrencesPerQuery, let candidate = generator.candidate(at: index) {
            if candidate >= window.end { break }
            if let end, candidate > end { break }
            if candidate >= start, candidate >= window.start {
                results.append(candidate)
            }
            index += 1
        }
        return results
    }

    /// The first occurrence of `rule` anchored at `start` strictly after `date` (Sprint 13: a recurring task's next due
    /// date), within three years.
    public func nextOccurrence(
        of rule: RecurrenceRule, start: Date, after date: Date, calendar: HouseholdCalendar
    ) -> Date? {
        let horizon = DateInterval(start: date, duration: 3 * 366 * 24 * 3600)
        return occurrences(of: rule, start: start, end: nil, in: horizon, calendar: calendar).first { $0 > date }
    }

    /// The first occurrence strictly after `date`, or nil if the series has ended.
    public func nextOccurrence(of series: RecurringSeries, after date: Date) -> Date? {
        let horizon = DateInterval(start: date, duration: 3 * 366 * 24 * 3600)
        return occurrences(of: series, in: horizon).first { $0 > date }
    }
}

/// Maps an index (0 = the series start's period) to the candidate date in that period.
private struct Generator {
    let rule: RecurrenceRule
    let start: Date
    let calendar: HouseholdCalendar
    let startParts: DateComponents

    init(rule: RecurrenceRule, start: Date, calendar: HouseholdCalendar) {
        self.rule = rule
        self.start = start
        self.calendar = calendar
        let wanted: Set<Calendar.Component> = [.year, .month, .day, .weekday, .hour, .minute, .second]
        self.startParts = calendar.calendar.dateComponents(wanted, from: start)
    }

    private var cal: Calendar { calendar.calendar }

    /// A safe lower bound for the index so long-running series do not iterate from their start every time.
    func firstUsefulIndex(for windowStart: Date) -> Int {
        guard windowStart > start else { return 0 }
        switch rule {
        case .daily(let interval):
            return max(0, calendar.dayDifference(from: start, to: windowStart) / interval - 1)
        case .weekly(let interval, _):
            return max(0, calendar.dayDifference(from: start, to: windowStart) / (7 * interval) - 1)
        case .monthlyOnDay, .monthlyOnWeekday:
            let months = cal.dateComponents([.month], from: calendar.startOfMonth(for: start), to: windowStart).month
            return max(0, (months ?? 0) - 1)
        case .yearly:
            let years = cal.dateComponents([.year], from: calendar.startOfYear(for: start), to: windowStart).year
            return max(0, (years ?? 0) - 1)
        }
    }

    func candidate(at index: Int) -> Date? {
        switch rule {
        case .daily(let interval):
            let firstDay = calendar.startOfDay(for: start)
            guard let day = cal.date(byAdding: .day, value: interval * index, to: firstDay) else { return nil }
            let parts = cal.dateComponents([.year, .month, .day], from: day)
            return localDate(year: parts.year, month: parts.month, day: parts.day)
        case .weekly(let interval, let weekday):
            let startWeekday = startParts.weekday ?? 1
            let firstOffset = (weekday - startWeekday + 7) % 7
            let firstDay = calendar.startOfDay(for: start)
            guard let day = cal.date(byAdding: .day, value: firstOffset + 7 * interval * index, to: firstDay) else {
                return nil
            }
            let parts = cal.dateComponents([.year, .month, .day], from: day)
            return localDate(year: parts.year, month: parts.month, day: parts.day)
        case .monthlyOnDay(let day):
            let (year, month) = monthOffset(index)
            return localDate(year: year, month: month, day: min(day, daysIn(year: year, month: month)))
        case .monthlyOnWeekday(let ordinal, let weekday):
            let (year, month) = monthOffset(index)
            let days = daysIn(year: year, month: month)
            guard let first = localDate(year: year, month: month, day: 1) else { return nil }
            let firstMatch = 1 + (weekday - cal.component(.weekday, from: first) + 7) % 7
            let day = ordinal > 0 ? firstMatch + 7 * (ordinal - 1) : firstMatch + 7 * ((days - firstMatch) / 7)
            return localDate(year: year, month: month, day: day)
        case .yearly(let month, let day):
            let year = (startParts.year ?? 0) + index
            return localDate(year: year, month: month, day: min(day, daysIn(year: year, month: month)))
        }
    }

    private func monthOffset(_ index: Int) -> (year: Int, month: Int) {
        let total = (startParts.year ?? 0) * 12 + (startParts.month ?? 1) - 1 + index
        return (total / 12, total % 12 + 1)
    }

    private func daysIn(year: Int, month: Int) -> Int {
        guard let first = localDate(year: year, month: month, day: 1) else { return 28 }
        return cal.range(of: .day, in: .month, for: first)?.count ?? 28
    }

    private func localDate(year: Int?, month: Int?, day: Int?) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = startParts.hour
        parts.minute = startParts.minute
        parts.second = startParts.second
        return cal.date(from: parts)
    }
}
