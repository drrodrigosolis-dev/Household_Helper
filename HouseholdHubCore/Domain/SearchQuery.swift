import Foundation

/// Deterministic search (Sprint 14 decisions 1–2): every word of the query must appear somewhere in a record's text,
/// ignoring case and accents ("cafe" finds "Café"). A word that reads as an amount ("47.50", "47,50", "12") also
/// matches a record whose amount is exactly that. No AI, no index: the household's data is small.
public struct SearchQuery: Equatable, Sendable {
    /// Folded words, in query order.
    public let words: [String]
    private let locale: Locale

    public init(_ text: String, locale: Locale = .current) {
        self.locale = locale
        self.words = text.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0), locale: locale) }
    }

    public var isEmpty: Bool { words.isEmpty }

    /// - Parameters:
    ///   - fields: the record's searchable text (name, notes, merchant, category…); nil entries are skipped.
    ///   - amount: the record's amount, if it has one.
    public func matches(_ fields: [String?], amount: Money? = nil) -> Bool {
        guard !isEmpty else { return true }
        let text = fields.compactMap { $0 }.map { Self.fold($0, locale: locale) }.joined(separator: " ")
        return words.allSatisfy { word in
            text.contains(word) || amount.map { matchesAmount(word, $0) } == true
        }
    }

    /// "47.50" or "47,50" matches 4750 minor units of a two-decimal currency; "47" matches 4700.
    private func matchesAmount(_ word: String, _ amount: Money) -> Bool {
        let normalized = word.replacingOccurrences(of: ",", with: ".")
        guard normalized.allSatisfy({ $0.isNumber || $0 == "." }), normalized.filter({ $0 == "." }).count <= 1,
            let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
            let currency = try? Currency(code: amount.currencyCode),
            let wanted = try? Money(decimal: value, currency: currency)
        else { return false }
        return wanted.minorUnits == amount.minorUnits
    }

    static func fold(_ text: String, locale: Locale) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }
}
