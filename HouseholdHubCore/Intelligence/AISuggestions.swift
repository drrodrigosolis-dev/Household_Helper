import Foundation

/// What an on-device model may propose for a Quick Add text (spec §12.2 "structured output"). Every field is a raw
/// proposal; `QuickAddSuggestionValidator` decides what, if anything, reaches the editable fields. A description is
/// accepted only in the note's own words (owner decision 2026-09-26 to allow it, with that guard).
public struct QuickAddSuggestion: Equatable, Sendable {
    /// The amount exactly as the model wrote it; read with the §25 number grammar, never loosely.
    public var amount: String?
    /// "expense" or "income".
    public var type: String?
    public var categoryName: String?
    /// Days from today, e.g. -1 for yesterday.
    public var dayOffset: Int?
    /// A tidier description, e.g. "Lunch with Sam" for "twelve dollars lunch with sam".
    public var description: String?

    public init(
        amount: String? = nil, type: String? = nil, categoryName: String? = nil, dayOffset: Int? = nil,
        description: String? = nil
    ) {
        self.amount = amount
        self.type = type
        self.categoryName = categoryName
        self.dayOffset = dayOffset
        self.description = description
    }
}

/// The validated result: only values that passed every check, for fields the deterministic parser left empty.
public struct ValidatedQuickAdd: Equatable, Sendable {
    public var amount: Money?
    public var type: TransactionType?
    public var categoryID: UUID?
    public var occurredAt: Date?
    public var description: String?

    public init(
        amount: Money? = nil, type: TransactionType? = nil, categoryID: UUID? = nil, occurredAt: Date? = nil,
        description: String? = nil
    ) {
        self.amount = amount
        self.type = type
        self.categoryID = categoryID
        self.occurredAt = occurredAt
        self.description = description
    }

    public var isEmpty: Bool {
        amount == nil && type == nil && categoryID == nil && occurredAt == nil && description == nil
    }
}

/// Deterministic checks on model output (spec §12.2 "validation layer"). The §25 parse always wins: a suggestion only
/// fills a field the parser left empty (Sprint 7 default 3).
public enum QuickAddSuggestionValidator {
    /// Suggested dates reach back at most a month and never into the future.
    public static let maxDayOffset = 31
    /// A sanity cap in major units; larger amounts are typed, not suggested.
    public static let maxAmount: Decimal = 1_000_000
    public static let maxDescriptionLength = 80
    /// Spelled-out amounts ("twelve dollars") belong in the amount field, not the description.
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
        "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "dollar", "dollars", "bucks",
        "cents",
    ]

    public static func validate(
        _ suggestion: QuickAddSuggestion, parsed: QuickAddParse, note: String = "", currency: Currency,
        categories: [QuickAddCategoryOption], now: Date, calendar: HouseholdCalendar
    ) -> ValidatedQuickAdd {
        var result = ValidatedQuickAdd()
        if parsed.amount == nil, let text = suggestion.amount?.trimmingCharacters(in: .whitespaces) {
            result.amount = amount(text, currency: currency)
        }
        // Income only when the model says so and the parser saw no sign; expense is already the default.
        let type = suggestion.type.flatMap { TransactionType(rawValue: $0.lowercased()) }
        if parsed.type == .expense, type == .income {
            result.type = .income
        }
        if parsed.categoryID == nil, let name = suggestion.categoryName?.trimmingCharacters(in: .whitespaces),
            let match = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
            match.kind.allows(result.type ?? parsed.type)
        {
            result.categoryID = match.id
        }
        if !parsed.dateRecognized, let offset = suggestion.dayOffset, (-maxDayOffset)...(-1) ~= offset {
            result.occurredAt = calendar.calendar.date(byAdding: .day, value: offset, to: now)
        }
        result.description = description(suggestion.description, note: note)
        return result
    }

    /// A single short line that shares at least one word with the note, so the model tidies the user's words rather
    /// than inventing new ones. Digits and number words are not allowed: amounts belong in the amount field. Control
    /// and format characters (tabs, bidi overrides, zero-width marks) are rejected so nothing hidden reaches notes.
    static func description(_ proposed: String?, note: String) -> String? {
        guard let text = proposed?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
            text.count <= maxDescriptionLength, !text.contains(where: { $0.isNewline || $0.isNumber }),
            !text.unicodeScalars.contains(where: { [.control, .format].contains($0.properties.generalCategory) })
        else { return nil }
        let lowered = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard lowered.isDisjoint(with: numberWords) else { return nil }
        func words(_ string: String) -> Set<String> {
            Set(
                string.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                    .filter { $0.count >= 3 })
        }
        return words(text).isDisjoint(with: words(note)) ? nil : text
    }

    /// A positive amount in the §25 grammar with no more decimals than the currency has, under the sanity cap.
    static func amount(_ text: String, currency: Currency) -> Money? {
        guard let value = QuickAddParser.plainAmount(text), value > 0, value <= maxAmount,
            let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0,
            money.decimalValue == value
        else { return nil }
        return money
    }
}

/// What the Quick Add form looks like when a suggestion arrives.
public struct QuickAddFormSnapshot: Equatable, Sendable {
    /// The selected segment's transaction type; nil for Wishlist and Task, which suggestions never touch.
    public var type: TransactionType?
    public var amountIsEmpty: Bool
    public var categoryID: UUID?
    public var occurredAt: Date
    /// The notes field as it is now; a suggested description replaces it only while it still holds the parser's text.
    public var notes: String

    public init(type: TransactionType?, amountIsEmpty: Bool, categoryID: UUID?, occurredAt: Date, notes: String = "") {
        self.type = type
        self.amountIsEmpty = amountIsEmpty
        self.categoryID = categoryID
        self.occurredAt = occurredAt
        self.notes = notes
    }
}

/// Decides which validated values may still be written into the form, which may have changed while the model was
/// thinking. A value the user typed or picked is never replaced.
public enum QuickAddSuggestionMerge {
    public static func fieldsToApply(
        _ suggestion: ValidatedQuickAdd, form: QuickAddFormSnapshot, parsed: QuickAddParse,
        categories: [QuickAddCategoryOption]
    ) -> ValidatedQuickAdd {
        guard let selected = form.type else { return ValidatedQuickAdd() }
        var result = ValidatedQuickAdd()
        if form.amountIsEmpty {
            result.amount = suggestion.amount
        }
        if suggestion.type == .income, selected == .expense {
            result.type = .income
        }
        let finalType = result.type ?? selected
        if form.categoryID == nil, let id = suggestion.categoryID,
            categories.contains(where: { $0.id == id && $0.kind.allows(finalType) })
        {
            result.categoryID = id
        }
        // Only a date that is still the parser's own default: not one the text named, not one the user picked.
        if !parsed.dateRecognized, form.occurredAt == parsed.occurredAt {
            result.occurredAt = suggestion.occurredAt
        }
        if form.notes == parsed.description, suggestion.description != parsed.description {
            result.description = suggestion.description
        }
        return result
    }
}

/// A name from the report with its amount, e.g. a category and what was spent in it.
public struct NamedFigure: Equatable, Sendable {
    public let name: String
    public let amount: String

    public init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }
}

/// Facts the analytics narrative may use: the report's own computed figures, never individual transactions
/// (Sprint 7 default 4). The model sees each figure only as a placeholder such as `{income}` and the app fills in
/// the formatted value afterwards, so the text can't quote a changed, partial, or invented number.
public struct AnalyticsFacts: Equatable, Sendable {
    public enum Balance: Equatable, Sendable {
        case surplus
        case deficit
        case even
    }

    public let periodTitle: String
    public let income: String
    public let expense: String
    public let net: String
    public let balance: Balance
    public let topCategories: [NamedFigure]
    public let topMerchants: [NamedFigure]
    /// Whether the figures include pending transactions (the owner's Analytics switch).
    public let includesPending: Bool

    public init(
        periodTitle: String, income: String, expense: String, net: String, balance: Balance,
        topCategories: [NamedFigure], topMerchants: [NamedFigure], includesPending: Bool = false
    ) {
        self.includesPending = includesPending
        self.periodTitle = periodTitle
        self.income = income
        self.expense = expense
        self.net = net
        self.balance = balance
        self.topCategories = topCategories
        self.topMerchants = topMerchants
    }

    /// Placeholder → the formatted value the app writes in its place.
    public var values: [String: String] {
        var values = ["{period}": periodTitle, "{income}": income, "{expenses}": expense, "{net}": net]
        for (index, category) in topCategories.enumerated() {
            values["{category\(index + 1)}"] = category.amount
        }
        for (index, merchant) in topMerchants.enumerated() {
            values["{merchant\(index + 1)}"] = merchant.amount
        }
        return values
    }

    /// Names the text may repeat as written (they can contain digits, e.g. "7-Eleven").
    public var names: [String] {
        (topCategories + topMerchants).map(\.name)
    }

    /// The model's only source. It carries no digits of its own: figures are placeholders, and how income and
    /// spending compare is stated in words so the model needn't do arithmetic.
    public var prompt: String {
        var lines = ["Period: {period}", "Income: {income}", "Expenses: {expenses}", "Net: {net}"]
        switch balance {
        case .surplus: lines.append("Income was more than spending.")
        case .deficit: lines.append("Spending was more than income.")
        case .even: lines.append("Income and spending were equal.")
        }
        lines.append(
            includesPending
                ? "The figures include pending transactions that have not posted yet."
                : "The figures include posted transactions only.")
        if !topCategories.isEmpty {
            let list = topCategories.enumerated().map { "\($1.name) {category\($0 + 1)}" }
            lines.append("Largest spending categories: " + list.joined(separator: "; "))
        }
        if !topMerchants.isEmpty {
            let list = topMerchants.enumerated().map { "\($1.name) {merchant\($0 + 1)}" }
            lines.append("Top merchants: " + list.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

public enum NarrativeValidator {
    public static let maxLength = 600

    /// Accepts a narrative only if it is short, writes no digits of its own, and uses only known placeholders; then
    /// fills the placeholders with the report's formatted figures. Anything else is rejected, never repaired.
    public static func validate(_ text: String, facts: AnalyticsFacts) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        let values = facts.values
        let placeholders = trimmed.matches(of: /\{[a-z0-9]+\}/).map { String($0.output) }
        guard placeholders.allSatisfy({ values[$0] != nil }) else { return nil }
        var rest = trimmed
        for key in Set(placeholders) {
            rest = rest.replacingOccurrences(of: key, with: " ")
        }
        // Longest names first so a name containing another is removed whole.
        for name in facts.names.sorted(by: { $0.count > $1.count }) where !name.isEmpty {
            rest = rest.replacingOccurrences(of: name, with: " ")
        }
        guard !rest.contains(where: { $0.isNumber || $0 == "{" || $0 == "}" }) else { return nil }
        var filled = trimmed
        for key in Set(placeholders) {
            filled = filled.replacingOccurrences(of: key, with: values[key] ?? key)
        }
        return filled
    }
}
