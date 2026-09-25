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
    /// Remaining free text after the amount, keywords, tags, and date word are removed.
    public var description: String
    public var categoryID: UUID?
    public var occurredAt: Date

    public init(amount: Money?, type: TransactionType, description: String, categoryID: UUID?, occurredAt: Date) {
        self.amount = amount
        self.type = type
        self.description = description
        self.categoryID = categoryID
        self.occurredAt = occurredAt
    }
}

/// The non-AI Quick Add grammar (spec §25). It never guesses: no category from meaning, no merchant normalization,
/// no recurrence, no currency detection (§25.3). Keywords are English in v1.
///
///     47.50 coffee            → expense 47.50, "coffee"
///     + 1200 paycheck         → income 1200.00, "paycheck"
///     32.10 groceries #food   → expense 32.10, category whose name contains "food"
///     18 lunch yesterday      → expense 18.00, dated yesterday
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

        if tokens.first == "+" {
            type = .income
            tokens.removeFirst()
        } else if let first = tokens.first, first.hasPrefix("+"), amountValue(String(first.dropFirst())) != nil {
            type = .income
            tokens[0] = String(first.dropFirst())
        }
        if let index = tokens.firstIndex(where: { Self.incomeWords.contains($0.lowercased()) }) {
            type = .income
            tokens.remove(at: index)
        }

        var amount: Money?
        if let index = tokens.firstIndex(where: { amountValue($0) != nil }), let value = amountValue(tokens[index]) {
            tokens.remove(at: index)
            if let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0 {
                amount = money
            }
        }

        var occurredAt = now
        if let index = tokens.firstIndex(where: { dayOffset(for: $0, now: now) != nil }),
            let offset = dayOffset(for: tokens[index], now: now)
        {
            occurredAt = calendar.calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            tokens.remove(at: index)
        }

        let tags = tokens.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        tokens.removeAll { $0.hasPrefix("#") && $0.count > 1 }
        let categoryID = tags.first.flatMap { matchCategory($0, for: type) }

        let description = tokens.joined(separator: " ")
        return QuickAddParse(
            amount: amount, type: type, description: description, categoryID: categoryID, occurredAt: occurredAt)
    }

    // MARK: Grammar pieces

    private static let incomeWords: Set<String> = ["income", "received"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// A plain number: `47`, `47.50`, `1,200.50`, optionally prefixed with `$`. Anything else is description text.
    private func amountValue(_ token: String) -> Decimal? {
        let body = token.hasPrefix("$") ? String(token.dropFirst()) : token
        guard body.wholeMatch(of: /\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?/) != nil else { return nil }
        let plain = body.replacingOccurrences(of: ",", with: "")
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Days back for `today`, `yesterday`, or a weekday name (its most recent occurrence, today included).
    private func dayOffset(for token: String, now: Date) -> Int? {
        let word = token.lowercased()
        if word == "today" { return 0 }
        if word == "yesterday" { return 1 }
        let index = Self.weekdays.firstIndex { $0 == word || ($0.prefix(3) == word && word.count == 3) }
        guard let index else { return nil }
        let today = calendar.calendar.component(.weekday, from: now)
        return (today - (index + 1) + 7) % 7
    }

    /// Case-insensitive substring match against category names, restricted to kinds valid for `type` (§25.2).
    private func matchCategory(_ tag: String, for type: TransactionType) -> UUID? {
        categories.first { $0.kind.allows(type) && $0.name.range(of: tag, options: .caseInsensitive) != nil }?.id
    }
}
