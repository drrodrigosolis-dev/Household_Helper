import Foundation

/// Why a Siri entry can't become a draft (Sprint 25). Nothing is saved in any case.
public enum SiriEntryError: Error, Equatable, Sendable {
    /// Onboarding isn't finished, so there is no household currency yet.
    case notSetUp
    /// Nothing was said, or only a price.
    case emptyText
    /// "for <amount>" named zero, more decimals than the currency has, or more than `Money.maxPlanMinorUnits`.
    case invalidPrice
}

/// Text shared by the Siri grammars. Dictation adds punctuation ("headphones for 149.", "40,", "¿…?"), which the §25
/// number and day words don't read, so sentence marks are dropped from both ends of every word first.
public enum SiriText {
    static let trailingMarks = CharacterSet(charactersIn: ".,;:!?¡¿…")

    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: trailingMarks) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Every amount written in digits in `text`, in the §25 number grammar. A model's amount must be one of these:
    /// it may choose between the numbers the person said, never invent one.
    static func writtenAmounts(in text: String) -> [Decimal] {
        normalize(text).split(separator: " ").compactMap { QuickAddParser.plainAmount(String($0)) }
    }
}

/// What "Add to my wishlist" understood: a name and, when the person said one, a price.
public struct WishlistEntryDraft: Equatable, Sendable {
    public var name: String
    /// Nil when no price was said; the item is then saved with an unknown (zero) price.
    public var price: Money?

    public init(name: String, price: Money?) {
        self.name = name
        self.price = price
    }

    /// The draft the wishlist service stores; an unknown price is zero (`WishlistDraft.estimatedPrice`).
    public func wishlistDraft(currencyCode: String) -> WishlistDraft {
        WishlistDraft(name: name, estimatedPrice: price ?? .zero(currencyCode))
    }
}

/// The Add to Wishlist grammar (Sprint 25, owner answer 1): "<name> for <amount>", the amount optional. The price is
/// read only after a final "for" (or Spanish "por"), in the §25 number grammar ("149", "$149.99", "1,200"), and may
/// be followed by "dollars" / "bucks" / "dólares"; it is always in the household currency (no currency detection,
/// §25.3). Anything else stays in the name, so "gift for mom" is a name with no price and "iPhone 17" keeps its 17.
/// Numbers use the English format: "149,99" is not read as a price and stays in the name for the person to see in
/// the confirmation.
///
///     headphones for 149          → "headphones", 149.00
///     new sofa for $1,200.50      → "new sofa", 1,200.50
///     audífonos por 149 dólares   → "audífonos", 149.00
///     gift for mom                → "gift for mom", no price
public enum WishlistEntry {
    static let priceWords: Set<String> = ["for", "por"]
    static let currencyWords: Set<String> = ["dollar", "dollars", "buck", "bucks", "dolar", "dolares"]

    public static func draft(text: String, settings: SettingsSnapshot?) throws -> WishlistEntryDraft {
        guard let settings, settings.onboardingCompleted, let currency = try? Currency(code: settings.currencyCode)
        else { throw SiriEntryError.notSetUp }
        var tokens = SiriText.normalize(text).split(separator: " ").map(String.init)
        if let last = tokens.last, currencyWords.contains(QuickAddParser.fold(last)), tokens.count >= 3,
            QuickAddParser.plainAmount(tokens[tokens.count - 2]) != nil
        {
            tokens.removeLast()
        }
        var price: Money?
        if tokens.count >= 2, priceWords.contains(QuickAddParser.fold(tokens[tokens.count - 2])),
            let value = QuickAddParser.plainAmount(tokens[tokens.count - 1])
        {
            price = try validPrice(value, currency: currency)
            tokens.removeLast(2)
        }
        let name = tokens.joined(separator: " ")
        guard !name.isEmpty else { throw SiriEntryError.emptyText }
        return WishlistEntryDraft(name: name, price: price)
    }

    /// A positive price with no more decimals than the currency has, within the plan limit.
    static func validPrice(_ value: Decimal, currency: Currency) throws -> Money {
        guard value > 0, let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0,
            money.minorUnits <= Money.maxPlanMinorUnits, money.decimalValue == value
        else { throw SiriEntryError.invalidPrice }
        return money
    }
}

/// The Add a Task grammar (Sprint 25, owner answer 1): the whole dictated text is the title, numbers and date words
/// included; the task goes to the first column (owner answer 2).
public enum TaskEntry {
    public static func draft(text: String) throws -> TaskDraft {
        // Dictation ends the sentence with a period; it isn't part of the title.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".")).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw SiriEntryError.emptyText }
        return TaskDraft(title: title)
    }
}
