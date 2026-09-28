import Foundation

/// Reads a time of day from entry text (owner request 2026-09-28), for Quick Add, batch task lines, and Siri tasks.
/// English and Spanish, whatever the device language, ignoring case, accents, and punctuation around a word:
///
///     3pm  3 pm  3:30pm  3:30 p.m.  12am           12-hour clock: the hour is 1–12 ("13pm" is not a time)
///     15:30  3:30                                  a colon is a 24-hour clock: 0–23 hours, 00–59 minutes
///     noon  midnight  mediodía  medianoche         12:00 and 0:00
///     3 de la tarde  10 de la noche                1–11 plus 12; "12 de la tarde" is noon, "12 de la noche" midnight
///     8 de la mañana  5 de la madrugada            1–11 as said; "12 de la mañana" is 0:00
///     at 3pm  at 15:30  at noon                    "at" is part of the time when a time follows it
///     a las 3  a las 15:30  a las 3pm  a la 1      "a las N" alone is hour N (0–23) on a 24-hour clock
///     a mediodía  al mediodía  a medianoche
///
/// A bare number is never a time on its own ("buy 3 eggs", "40 lunch"): it needs am/pm, a colon, "de la …", or
/// "a las"/"a la" in front. "at 3" is not a time either, since English "at 3" is too often 3 pm to read it as 3:00.
/// Anything invalid ("25:00", "13pm", "3:75") is not a time, and its words stay in the text.
public enum TimeOfDayParser {
    /// A time found in a list of words.
    public struct Match: Equatable, Sendable {
        /// Minutes after local midnight, 0...1439 (`TimeOfDay`).
        public var minutes: Int
        /// The words the time spans, "at"/"a las"/"de la tarde" included, as indexes into the words given.
        public var tokens: Range<Int>

        public init(minutes: Int, tokens: Range<Int>) {
            self.minutes = minutes
            self.tokens = tokens
        }
    }

    /// The first time in `tokens` (whitespace-separated words), or nil when there is none.
    public static func firstMatch(in tokens: [String]) -> Match? {
        let words = tokens.map(clean)
        for start in words.indices {
            if let found = match(words, at: start) {
                return found
            }
        }
        return nil
    }

    /// The day a task is due when its text names a time but no date word: today while the time is still ahead of
    /// `now`, tomorrow once it has passed (a time exactly at `now` has passed). Start of that day in `calendar`.
    public static func dueDay(forMinutes minutes: Int, now: Date, calendar: HouseholdCalendar) -> Date {
        let today = TimeOfDay.date(minutes: minutes, onDayOf: now, calendar: calendar)
        if today > now {
            return calendar.startOfDay(for: now)
        }
        let tomorrow = calendar.calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.startOfDay(for: tomorrow)
    }

    /// When a transaction happened, for a time said with it: `minutes` on the day of `day`, never after `now`, since
    /// Quick Add records what already happened. With no day word (`dayNamed` false), a time still ahead today means
    /// yesterday ("8pm dinner" typed at 9 am is last night). With a day word naming today, a later time is `now`.
    public static func pastInstant(
        minutes: Int, onDayOf day: Date, dayNamed: Bool, now: Date, calendar: HouseholdCalendar
    ) -> Date {
        let timed = TimeOfDay.date(minutes: minutes, onDayOf: day, calendar: calendar)
        guard timed > now else { return timed }
        if dayNamed {
            return now
        }
        let yesterday = calendar.calendar.date(byAdding: .day, value: -1, to: day) ?? day
        return min(TimeOfDay.date(minutes: minutes, onDayOf: yesterday, calendar: calendar), now)
    }

    // MARK: Grammar

    static let namedTimes: [String: Int] = ["noon": 12 * 60, "midnight": 0, "mediodia": 12 * 60, "medianoche": 0]

    /// Spanish parts of the day after "de la": whether hours 1–11 are after noon, and the hour 12 means.
    static let periods: [String: (afternoon: Bool, twelve: Int)] = [
        "manana": (false, 0), "madrugada": (false, 0), "tarde": (true, 12), "noche": (true, 0),
    ]

    static let edgeMarks = CharacterSet(charactersIn: ".,;:!?¡¿…\"'()")

    /// Lowercased, accents folded, sentence marks trimmed from both ends ("P.M." → "p.m", "15:30," → "15:30").
    static func clean(_ token: String) -> String {
        QuickAddParser.fold(token).trimmingCharacters(in: edgeMarks)
    }

    private static func match(_ words: [String], at start: Int) -> Match? {
        let next = start + 1
        if words[start] == "at", let found = core(words, at: next, bareHour: false) {
            return Match(minutes: found.minutes, tokens: start..<found.end)
        }
        if words[start] == "a", next < words.count, words[next] == "las" || words[next] == "la",
            let found = core(words, at: next + 1, bareHour: true)
        {
            return Match(minutes: found.minutes, tokens: start..<found.end)
        }
        if words[start] == "a" || words[start] == "al", next < words.count, let minutes = namedTimes[words[next]] {
            return Match(minutes: minutes, tokens: start..<(next + 1))
        }
        if let found = core(words, at: start, bareHour: false) {
            return Match(minutes: found.minutes, tokens: start..<found.end)
        }
        return nil
    }

    /// The time starting at `index` and the index after it. `bareHour`: a plain hour counts ("a las 3").
    private static func core(_ words: [String], at index: Int, bareHour: Bool) -> (minutes: Int, end: Int)? {
        guard index < words.count else { return nil }
        let word = words[index]
        if let minutes = namedTimes[word] {
            return (minutes, index + 1)
        }
        // Every other time starts with a digit; checking first keeps the regexes off ordinary words while typing.
        guard word.first?.isASCII == true, word.first?.isNumber == true else { return nil }
        if let parts = word.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?([ap])\.?m/) {
            guard let minutes = twelveHour(parts.1, parts.2, afternoon: parts.3 == "p") else { return nil }
            return (minutes, index + 1)
        }
        guard let clock = word.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?/) else { return nil }
        if index + 1 < words.count, let suffix = words[index + 1].wholeMatch(of: /([ap])\.?m/) {
            guard let minutes = twelveHour(clock.1, clock.2, afternoon: suffix.1 == "p") else { return nil }
            return (minutes, index + 2)
        }
        if index + 3 < words.count, words[index + 1] == "de", words[index + 2] == "la",
            let period = periods[words[index + 3]]
        {
            guard let hour = hourValue(clock.1, in: 1...12), let minute = minuteValue(clock.2) else { return nil }
            let hours = hour == 12 ? period.twelve : hour + (period.afternoon ? 12 : 0)
            return (hours * 60 + minute, index + 4)
        }
        guard clock.2 != nil || bareHour, let hour = hourValue(clock.1, in: 0...23), let minute = minuteValue(clock.2)
        else { return nil }
        return (hour * 60 + minute, index + 1)
    }

    /// 1–12 with am/pm: 12 am is 0:00, 12 pm is 12:00.
    private static func twelveHour(_ hourText: Substring, _ minuteText: Substring?, afternoon: Bool) -> Int? {
        guard let hour = hourValue(hourText, in: 1...12), let minute = minuteValue(minuteText) else { return nil }
        return ((hour % 12) + (afternoon ? 12 : 0)) * 60 + minute
    }

    /// The hour when it is within `range`, nil otherwise.
    private static func hourValue(_ text: Substring, in range: ClosedRange<Int>) -> Int? {
        guard let value = Int(text), range.contains(value) else { return nil }
        return value
    }

    /// 0 when no minutes were written, the minutes when they are 00–59, nil otherwise.
    private static func minuteValue(_ text: Substring?) -> Int? {
        guard let text else { return 0 }
        guard let value = Int(text), (0...59).contains(value) else { return nil }
        return value
    }
}
