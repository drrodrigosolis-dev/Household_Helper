import Foundation

/// Reads one task line (Sprint 17, decision 3). One date word becomes the due date and looks forward: `today`/`hoy`,
/// `tomorrow`/`mañana`, or a weekday meaning its next occurrence, today included. Weekdays are full names (English or
/// Spanish) or the English `tue`, `thu`, `fri`; other three-letter forms are ordinary words too often ("sun cream",
/// "ir al mar"), so they stay in the title. A time of day (`TimeOfDayParser`: "3pm", "a las 15:30", "noon") becomes
/// the due time; with no date word the task is due today while that time is still ahead of `now`, tomorrow once it
/// has passed. Everything else, numbers too, stays in the title ("buy 2 lightbulbs"). A line that is only date and
/// time words keeps them all as the title.
public struct TaskLineParser: Sendable {
    public let calendar: HouseholdCalendar

    public init(calendar: HouseholdCalendar) {
        self.calendar = calendar
    }

    /// Unambiguous short forms, as indexes into `QuickAddParser.weekdays`.
    static let shortWeekdays = ["tue": 2, "thu": 4, "fri": 5]

    public struct Result: Equatable, Sendable {
        public var title: String
        public var dueDate: Date?
        /// Minutes after local midnight on the due day; set only together with `dueDate`.
        public var dueTimeMinutes: Int?
    }

    public func parse(_ text: String, now: Date) -> Result {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens = words
        // The time first: "8 de la mañana" holds "mañana", which alone is a date word.
        let time = TimeOfDayParser.firstMatch(in: tokens)
        if let time {
            tokens.removeSubrange(time.tokens)
        }
        // The last date word wins: dates usually trail ("call plumber friday").
        let dateIndex = tokens.lastIndex(where: { daysAhead(for: $0, now: now) != nil })
        guard tokens.count > (dateIndex == nil ? 0 : 1) else {
            return Result(title: words.joined(separator: " "), dueDate: nil)
        }
        var dueDate: Date?
        if let dateIndex, let ahead = daysAhead(for: tokens[dateIndex], now: now) {
            let day = calendar.calendar.date(byAdding: .day, value: ahead, to: now) ?? now
            dueDate = calendar.startOfDay(for: day)
            tokens.remove(at: dateIndex)
        } else if let time {
            dueDate = TimeOfDayParser.dueDay(forMinutes: time.minutes, now: now, calendar: calendar)
        }
        return Result(title: tokens.joined(separator: " "), dueDate: dueDate, dueTimeMinutes: time?.minutes)
    }

    /// Days ahead for a date word, or nil when the token isn't one. Trailing punctuation is ignored ("friday,").
    func daysAhead(for token: String, now: Date) -> Int? {
        let word = QuickAddParser.fold(token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")))
        if word == "today" || word == "hoy" { return 0 }
        if word == "tomorrow" || word == "manana" { return 1 }
        guard
            let index = QuickAddParser.weekdays.firstIndex(of: word)
                ?? QuickAddParser.spanishWeekdays.firstIndex(of: word)
                ?? Self.shortWeekdays[word]
        else { return nil }
        let today = calendar.calendar.component(.weekday, from: now)
        return (index + 1 - today + 7) % 7
    }
}

/// Reads one wishlist line (Sprint 17, decision 4): the first plain number is the price ("250 new bike",
/// "$1,200 sofa"), a `#tag` picks an expense category like Quick Add, the rest is the name.
public struct WishlistLineParser: Sendable {
    public let currency: Currency
    public let categories: [QuickAddCategoryOption]

    public init(currency: Currency, categories: [QuickAddCategoryOption]) {
        self.currency = currency
        self.categories = categories
    }

    public struct Result: Equatable, Sendable {
        public var name: String
        /// Nil when the line has no price (unknown); never zero or negative.
        public var price: Money?
        /// The number was above `Money.maxPlanMinorUnits`: most likely a typo, so the line is not added.
        public var priceTooLarge: Bool
        public var categoryID: UUID?
    }

    public func parse(_ text: String) -> Result {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var price: Money?
        var tooLarge = false
        if let index = tokens.firstIndex(where: { QuickAddParser.plainAmount($0) != nil }),
            let value = QuickAddParser.plainAmount(tokens[index])
        {
            tokens.remove(at: index)
            if value > 0 {
                // A number too large for Money at all is as suspicious as one over the plan limit.
                let money = try? Money(decimal: value, currency: currency)
                if let money, money.minorUnits > 0, money.minorUnits <= Money.maxPlanMinorUnits {
                    price = money
                } else if money == nil || (money?.minorUnits ?? 0) > Money.maxPlanMinorUnits {
                    tooLarge = true
                }
            }
        }
        // The first #tag that names an expense category picks it and is removed; any other tag stays in the name.
        var categoryID: UUID?
        if let index = tokens.firstIndex(where: { $0.hasPrefix("#") && $0.count > 1 }) {
            let tag = String(tokens[index].dropFirst())
            categoryID =
                categories.first {
                    $0.kind.allows(.expense) && $0.name.range(of: tag, options: .caseInsensitive) != nil
                }?.id
            if categoryID != nil {
                tokens.remove(at: index)
            }
        }
        return Result(
            name: tokens.joined(separator: " "), price: price, priceTooLarge: tooLarge, categoryID: categoryID)
    }
}

/// What a batch creates: every line becomes the same kind (Sprint 17, owner answer "one type per batch").
public enum BatchAddKind: String, CaseIterable, Sendable {
    case tasks
    case wishlist
}

/// Why a pasted line is left out of the batch.
public enum BatchSkipReason: Equatable, Sendable {
    /// Nothing is left once the date word, price, or tag is read.
    case noText
    /// Ticked in the pasted checklist ("- [x] milk"): already done, so not added as a new item.
    case checkedOff
    case priceTooLarge
    /// Past `BatchAddPlanner.maxItems`.
    case overLimit
}

public enum BatchLineResult: Equatable, Sendable {
    case task(TaskDraft)
    case wishlist(WishlistDraft)
    case skipped(BatchSkipReason)

    public var taskDraft: TaskDraft? {
        guard case .task(let draft) = self else { return nil }
        return draft
    }

    public var wishlistDraft: WishlistDraft? {
        guard case .wishlist(let draft) = self else { return nil }
        return draft
    }

    public var skipReason: BatchSkipReason? {
        guard case .skipped(let reason) = self else { return nil }
        return reason
    }
}

/// One non-blank pasted line and what it becomes.
public struct BatchLine: Equatable, Sendable, Identifiable {
    /// 1-based line number in the pasted text.
    public let number: Int
    /// The line without its list marker.
    public let text: String
    public let result: BatchLineResult
    public var id: Int { number }
}

/// Turns pasted text into a preview of drafts (Sprint 17, decisions 2–5). Blank lines are dropped; list markers
/// from Notes or Markdown are stripped. Nothing is saved here: the services' batch methods save the valid drafts.
public struct BatchAddPlanner: Sendable {
    public static let maxItems = 200

    public let kind: BatchAddKind
    public let currency: Currency
    let tasks: TaskLineParser
    let wishes: WishlistLineParser

    public init(
        kind: BatchAddKind, currency: Currency, categories: [QuickAddCategoryOption], calendar: HouseholdCalendar
    ) {
        self.kind = kind
        self.currency = currency
        tasks = TaskLineParser(calendar: calendar)
        wishes = WishlistLineParser(currency: currency, categories: categories)
    }

    public func plan(_ text: String, now: Date) -> [BatchLine] {
        var lines: [BatchLine] = []
        var accepted = 0
        for (offset, raw) in text.components(separatedBy: .newlines).enumerated() {
            let body = Self.stripMarkers(raw)
            guard !body.isEmpty else { continue }
            let result: BatchLineResult
            if accepted >= Self.maxItems {
                result = .skipped(.overLimit)
            } else if Self.isCheckedOff(raw) {
                result = .skipped(.checkedOff)
            } else {
                result = read(body, now: now)
            }
            if result.skipReason == nil {
                accepted += 1
            }
            lines.append(BatchLine(number: offset + 1, text: body, result: result))
        }
        return lines
    }

    private func read(_ body: String, now: Date) -> BatchLineResult {
        switch kind {
        case .tasks:
            let line = tasks.parse(body, now: now)
            guard !line.title.isEmpty else { return .skipped(.noText) }
            let draft = TaskDraft(title: line.title, dueDate: line.dueDate, dueTimeMinutes: line.dueTimeMinutes)
            return .task(draft)
        case .wishlist:
            let line = wishes.parse(body)
            if line.priceTooLarge { return .skipped(.priceTooLarge) }
            guard !line.name.isEmpty else { return .skipped(.noText) }
            let price = line.price ?? Money.zero(currency.code)
            return .wishlist(WishlistDraft(name: line.name, estimatedPrice: price, categoryID: line.categoryID))
        }
    }

    /// A ticked checklist line: "[x] milk", "- [X] milk", "☑ milk", "✅ milk".
    static func isCheckedOff(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        return body.prefixMatch(of: /(?:[-*•–]\s+)?(?:\[[xX]\]|☑|✅)\s*/) != nil
    }

    /// Removes up to two leading list markers ("- [ ] milk" → "milk") and surrounding whitespace.
    static func stripMarkers(_ line: String) -> String {
        var body = line.trimmingCharacters(in: .whitespaces)
        for _ in 0..<2 {
            guard let match = body.prefixMatch(of: /(?:[-*•–]|\[[ xX]?\]|☐|☑|✅|\d{1,3}[.)])\s+/) else { break }
            body = String(body[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return body
    }
}

extension Array where Element == BatchLine {
    public var taskDrafts: [TaskDraft] { compactMap(\.result.taskDraft) }

    public var wishlistDrafts: [WishlistDraft] { compactMap(\.result.wishlistDraft) }
}
