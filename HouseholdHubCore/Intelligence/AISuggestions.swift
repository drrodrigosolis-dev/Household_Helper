import Foundation

/// What an on-device model may propose for a Quick Add text (spec §12.2 "structured output"). Every field is a raw
/// proposal; `QuickAddSuggestionValidator` decides what, if anything, reaches the editable fields.
public struct QuickAddSuggestion: Equatable, Sendable {
    public var amount: Decimal?
    /// "expense" or "income".
    public var type: String?
    public var categoryName: String?
    /// Days from today, e.g. -1 for yesterday.
    public var dayOffset: Int?
    public var description: String?

    public init(
        amount: Decimal? = nil, type: String? = nil, categoryName: String? = nil, dayOffset: Int? = nil,
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
    public static let maxDayOffset = 31
    public static let maxDescriptionLength = 80

    public static func validate(
        _ suggestion: QuickAddSuggestion, parsed: QuickAddParse, currency: Currency,
        categories: [QuickAddCategoryOption], now: Date, calendar: HouseholdCalendar
    ) -> ValidatedQuickAdd {
        var result = ValidatedQuickAdd()
        if parsed.amount == nil, let value = suggestion.amount, value > 0,
            let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0
        {
            result.amount = money
        }
        // Income only when the model says so and the parser saw no sign; expense is already the default.
        let type = suggestion.type.flatMap { TransactionType(rawValue: $0.lowercased()) }
        if parsed.type == .expense, type == .income {
            result.type = .income
        }
        let effectiveType = result.type ?? parsed.type
        if parsed.categoryID == nil, let name = suggestion.categoryName?.trimmingCharacters(in: .whitespaces),
            let match = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
            match.kind.allows(effectiveType)
        {
            result.categoryID = match.id
        }
        let parsedToday = calendar.startOfDay(for: parsed.occurredAt) == calendar.startOfDay(for: now)
        if parsedToday, let offset = suggestion.dayOffset, offset != 0, abs(offset) <= maxDayOffset {
            result.occurredAt = calendar.calendar.date(byAdding: .day, value: offset, to: now)
        }
        let text = suggestion.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if parsed.description.isEmpty, !text.isEmpty, text.count <= maxDescriptionLength {
            result.description = text
        }
        return result
    }
}

/// Facts the analytics narrative may use: the report's own computed figures, never individual transactions
/// (Sprint 7 default 4).
public struct AnalyticsFacts: Equatable, Sendable {
    public let periodTitle: String
    public let income: String
    public let expense: String
    public let net: String
    public let topCategories: [String]
    public let topMerchants: [String]

    public init(
        periodTitle: String, income: String, expense: String, net: String, topCategories: [String],
        topMerchants: [String]
    ) {
        self.periodTitle = periodTitle
        self.income = income
        self.expense = expense
        self.net = net
        self.topCategories = topCategories
        self.topMerchants = topMerchants
    }

    /// Plain-text facts handed to the model as its only source.
    public var prompt: String {
        var lines = [
            "Period: \(periodTitle)", "Income: \(income)", "Expenses: \(expense)", "Net: \(net)",
        ]
        if !topCategories.isEmpty {
            lines.append("Largest spending categories: " + topCategories.joined(separator: "; "))
        }
        if !topMerchants.isEmpty {
            lines.append("Top merchants: " + topMerchants.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

public enum NarrativeValidator {
    public static let maxLength = 600

    /// Accepts a narrative only if it is short and every amount it quotes appears in the facts, so the text cannot
    /// invent a figure.
    public static func validate(_ text: String, facts: AnalyticsFacts) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        let allowed = facts.prompt
        let figures = trimmed.matches(of: /\d[\d,.]*\d|\d/).map { String($0.output) }
        guard figures.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }
}
