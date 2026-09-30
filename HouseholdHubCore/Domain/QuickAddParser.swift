import Foundation

/// A category the parser may match a `#tag` against.
public struct QuickAddCategoryOption: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: CategoryKind

    public init(id: UUID, name: String, kind: CategoryKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// What the deterministic parser extracted (spec §25.2). Anything it could not read is left for the user.
public struct QuickAddParse: Equatable, Sendable {
    /// Nil when no positive amount was found; Quick Add then leaves the amount field empty (§25.4).
    public var amount: Money?
    public var type: TransactionType
    /// Remaining free text after the amount, keywords, tags, date word, and time are removed.
    public var description: String
    public var categoryID: UUID?
    /// When it happened: `now`, the named day at `now`'s time, or at the time the text named (`timeOfDayMinutes`).
    public var occurredAt: Date
    /// True when the text named the day ("today", "yesterday", a weekday) or a time of day. A named day or time is
    /// never replaced by a suggestion, even when it is today.
    public var dateRecognized: Bool
    /// The time of day the text named, minutes after local midnight; nil when it named none.
    public var timeOfDayMinutes: Int?

    public init(
        amount: Money?, type: TransactionType, description: String, categoryID: UUID?, occurredAt: Date,
        dateRecognized: Bool = false, timeOfDayMinutes: Int? = nil
    ) {
        self.amount = amount
        self.type = type
        self.description = description
        self.categoryID = categoryID
        self.occurredAt = occurredAt
        self.dateRecognized = dateRecognized
        self.timeOfDayMinutes = timeOfDayMinutes
    }
}

/// The non-AI Quick Add grammar (spec §25). It never guesses: no category from meaning, no merchant normalization,
/// no recurrence, no currency detection (§25.3). Keywords are English and Spanish (Sprint 16), whatever the device
/// language: "ingreso", "ayer", "hoy", weekday names; "gasto" marks an expense explicitly.
///
/// Type phrases (owner request 2026-09-28): a leading "+" is income and then no phrase is read. Otherwise the
/// phrases in `incomePhrases` ("got paid", "me pagaron") mean income and those in `expensePhrases` ("i had to pay",
/// "pagué") say expense explicitly. Phrases match whole words, ignoring case and accents; at each word the longest
/// phrase wins ("got paid" is income though it holds "paid"), and when the text holds several, the earliest wins.
/// Only that one phrase is removed from the description, with a "for"/"por" right after it (the amount may stand
/// between): "I paid 40 for gas" → "gas". A time of day (`TimeOfDayParser`) is removed too and sets the time.
///
///     47.50 coffee            → expense 47.50, "coffee"
///     + 1200 paycheck         → income 1200.00, "paycheck"
///     got paid 1200           → income 1200.00, ""
///     32.10 groceries #food   → expense 32.10, category whose name contains "food"
///     18 lunch yesterday      → expense 18.00, dated yesterday
///     18 lunch yesterday 1pm  → expense 18.00, dated yesterday at 13:00
public struct QuickAddParser: Sendable {
    public let currency: Currency
    public let categories: [QuickAddCategoryOption]
    public let calendar: HouseholdCalendar

    public init(currency: Currency, categories: [QuickAddCategoryOption], calendar: HouseholdCalendar) {
        self.currency = currency
        self.categories = categories
        self.calendar = calendar
    }

    public func parse(_ text: String, now: Date) -> QuickAddParse {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var type = TransactionType.expense
        var signed = false

        if tokens.first == "+" {
            type = .income
            signed = true
            tokens.removeFirst()
        } else if let first = tokens.first, first.hasPrefix("+"), amountValue(String(first.dropFirst())) != nil {
            type = .income
            signed = true
            tokens[0] = String(first.dropFirst())
        }
        // Where the type phrase stood, so a "for"/"por" right after it can go too.
        var phraseAt: Int?
        if !signed, let phrase = Self.typePhrase(in: tokens) {
            type = phrase.type
            tokens.removeSubrange(phrase.tokens)
            phraseAt = phrase.tokens.lowerBound
        }

        // The time before the amount: "3 pm" and "a las 3" hold numbers that are not amounts.
        let time = TimeOfDayParser.firstMatch(in: tokens)
        if let time {
            tokens.removeSubrange(time.tokens)
            if let at = phraseAt, time.tokens.upperBound <= at {
                phraseAt = at - time.tokens.count
            }
        }

        var amount: Money?
        if let index = tokens.firstIndex(where: { amountValue($0) != nil }), let value = amountValue(tokens[index]) {
            tokens.remove(at: index)
            if let at = phraseAt, index < at {
                phraseAt = at - 1
            }
            if let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0 {
                amount = money
            }
        }
        if let at = phraseAt, at < tokens.count, Self.phraseLinks.contains(Self.fold(tokens[at])) {
            tokens.remove(at: at)
        }

        var occurredAt = now
        var dateRecognized = false
        if let index = tokens.firstIndex(where: { dayOffset(for: $0, now: now) != nil }),
            let offset = dayOffset(for: tokens[index], now: now)
        {
            occurredAt = calendar.calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            dateRecognized = true
            tokens.remove(at: index)
        }
        if let time {
            occurredAt = TimeOfDayParser.pastInstant(
                minutes: time.minutes, onDayOf: occurredAt, dayNamed: dateRecognized, now: now, calendar: calendar)
            dateRecognized = true
        }

        let tags = tokens.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        tokens.removeAll { $0.hasPrefix("#") && $0.count > 1 }
        let categoryID = tags.first.flatMap { matchCategory($0, for: type) }

        let description = tokens.joined(separator: " ")
        return QuickAddParse(
            amount: amount, type: type, description: description, categoryID: categoryID, occurredAt: occurredAt,
            dateRecognized: dateRecognized, timeOfDayMinutes: time?.minutes)
    }

    // MARK: Grammar pieces

    /// Income phrases, folded (lowercase, no accents). Plain "got" is not one: "got 2 tickets" is an expense.
    static let incomePhrases: [String] = [
        "i got paid", "got paid", "i received", "received", "i earned", "earned", "i was paid", "income",
        "me pagaron", "cobre", "recibi", "recibido", "gane", "ingreso", "me depositaron",
    ]
    /// Expense is the default; these phrases only say so explicitly and are left out of the description.
    static let expensePhrases: [String] = [
        "i paid", "paid", "i had to pay", "had to pay", "i spent", "spent", "it was worth", "was worth", "it cost",
        "cost", "i bought", "bought", "pague", "tuve que pagar", "gaste", "costo", "compre", "gasto",
    ]
    /// Words dropped right after a type phrase ("I paid 40 for gas" → "gas").
    static let phraseLinks: Set<String> = ["for", "por"]

    /// A type phrase as folded words.
    struct TypePhrase: Sendable {
        let words: [String]
        let type: TransactionType

        init(_ phrase: String, _ type: TransactionType) {
            words = phrase.split(separator: " ").map(String.init)
            self.type = type
        }
    }

    /// Every phrase with its type, longest first, so at any word the longest phrase is tried first.
    static let typePhrases: [TypePhrase] = {
        let income = QuickAddParser.incomePhrases.map { TypePhrase($0, .income) }
        let expense = QuickAddParser.expensePhrases.map { TypePhrase($0, .expense) }
        return (income + expense).sorted { $0.words.count > $1.words.count }
    }()

    /// The earliest type phrase in `tokens` (the longest one at that word) and the words it spans.
    static func typePhrase(in tokens: [String]) -> (type: TransactionType, tokens: Range<Int>)? {
        let words = tokens.map { fold($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?¡¿")) }
        for start in words.indices {
            for phrase in typePhrases where words[start...].starts(with: phrase.words) {
                return (phrase.type, start..<(start + phrase.words.count))
            }
        }
        return nil
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let spanishWeekdays = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]

    /// Lowercased without accents, so "Miércoles" and "miercoles" read the same.
    static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// A plain number: `47`, `47.50`, `1,200.50`, optionally prefixed with `$`. Anything else is description text.
    private func amountValue(_ token: String) -> Decimal? {
        Self.plainAmount(token)
    }

    /// The same number grammar, shared with the suggestion validator so a model's amount is read the same way.
    static func plainAmount(_ token: String) -> Decimal? {
        let body = token.hasPrefix("$") ? String(token.dropFirst()) : token
        guard body.wholeMatch(of: /\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?/) != nil else { return nil }
        let plain = body.replacingOccurrences(of: ",", with: "")
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Days back for `today`, `yesterday`, or a weekday name (its most recent occurrence, today included).
    private func dayOffset(for token: String, now: Date) -> Int? {
        let word = Self.fold(token)
        if word == "today" || word == "hoy" { return 0 }
        if word == "yesterday" || word == "ayer" { return 1 }
        let matches: (String) -> Bool = { $0 == word || ($0.prefix(3) == word && word.count == 3) }
        guard let index = Self.weekdays.firstIndex(where: matches) ?? Self.spanishWeekdays.firstIndex(where: matches)
        else { return nil }
        let today = calendar.calendar.component(.weekday, from: now)
        return (today - (index + 1) + 7) % 7
    }

    /// Case-insensitive substring match against category names, restricted to kinds valid for `type` (§25.2).
    private func matchCategory(_ tag: String, for type: TransactionType) -> UUID? {
        categories.first { $0.kind.allows(type) && $0.name.range(of: tag, options: .caseInsensitive) != nil }?.id
    }
}
