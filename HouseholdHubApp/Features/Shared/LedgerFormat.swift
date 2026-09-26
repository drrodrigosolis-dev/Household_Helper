import HouseholdHubCore
import SwiftUI

/// Presentation helpers for money and categories. No accounting math happens here.
enum LedgerFormat {
    /// Amount with an explicit accounting sign ("-$47.50", "+$1,200.00") so meaning never depends on color alone.
    static func signedAmount(_ money: Money, type: TransactionType) -> String {
        switch type {
        case .expense:
            return ((try? money.negated()) ?? money).formatted()
        case .income:
            return money.decimalValue.formatted(.currency(code: money.currencyCode).sign(strategy: .always()))
        case .transfer:
            return money.formatted()
        }
    }

    /// Editable text for an amount field, in the current locale ("47.50" / "47,50").
    static func editableAmount(_ money: Money) -> String {
        let digits = Currency.minorUnitDigits(forCode: money.currencyCode)
        return money.decimalValue.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// Parses a user-typed amount in the current locale; nil unless it is a plain positive number.
    static func parseAmount(_ text: String, currencyCode: String, locale: Locale = .current) -> Money? {
        guard let value = parseDecimal(text, locale: locale), let currency = try? Currency(code: currencyCode),
            let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0
        else { return nil }
        return money
    }

    /// Strict locale-aware number parsing: plain digits, or correctly grouped thousands, with an optional
    /// fraction and leading minus. Anything else is nil, never a partial parse ("1,250.50" is 1250.50 in en_US,
    /// "12,5" is rejected there, "1.250,50" is 1250.50 in de_DE).
    static func parseDecimal(_ text: String, locale: Locale = .current) -> Decimal? {
        let body = text.trimmingCharacters(in: .whitespaces)
        let group = locale.groupingSeparator ?? ","
        let point = locale.decimalSeparator ?? "."
        let groups = [group, "\u{00A0}", "\u{202F}", " "].map(NSRegularExpression.escapedPattern(for:))
        let groupClass = "(?:" + groups.joined(separator: "|") + ")"
        let fraction = "(?:" + NSRegularExpression.escapedPattern(for: point) + "\\d+)?"
        let pattern = "-?(?:\\d{1,3}(?:" + groupClass + "\\d{3})+|\\d+)" + fraction
        guard let regex = try? Regex(pattern), body.wholeMatch(of: regex) != nil else { return nil }
        var plain = body
        for separator in [group, "\u{00A0}", "\u{202F}", " "] {
            plain = plain.replacingOccurrences(of: separator, with: "")
        }
        plain = plain.replacingOccurrences(of: point, with: ".")
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func typeLabel(_ type: TransactionType) -> LocalizedStringKey {
        switch type {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }

    static func statusText(_ status: TransactionStatus) -> String {
        switch status {
        case .posted: return String(localized: "Posted")
        case .pending: return String(localized: "Pending")
        case .cancelled: return String(localized: "Cancelled")
        }
    }

    static func statusLabel(_ status: TransactionStatus) -> LocalizedStringKey {
        switch status {
        case .posted: return "Posted"
        case .pending: return "Pending"
        case .cancelled: return "Cancelled"
        }
    }
}

extension ColorToken {
    /// An opaque token from a resolved SwiftUI color. `Color.Resolved.red/green/blue` are gamma-encoded sRGB
    /// components (the `linear…` ones are not used), clamped to 0...1.
    init(_ resolved: Color.Resolved) {
        func channel(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(red: channel(resolved.red), green: channel(resolved.green), blue: channel(resolved.blue))
    }
}

extension Color {
    init(_ token: ColorToken) {
        self.init(
            .sRGB, red: Double(token.red) / 255, green: Double(token.green) / 255, blue: Double(token.blue) / 255,
            opacity: Double(token.alpha) / 255)
    }
}

/// Money on one line: shrinks rather than wrapping mid-number at large text sizes.
struct AmountText: View {
    let text: String
    let font: Font

    init(_ text: String, font: Font = .body) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Category icon on its color. Decorative: rows describe the category in text for VoiceOver.
struct CategoryBadge: View {
    let icon: String
    let color: ColorToken?

    var body: some View {
        // Fixed glyph size: the badge is decorative (hidden from VoiceOver) and must not overflow its circle.
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(color.map { Color($0) } ?? Color.gray))
            .accessibilityHidden(true)
    }
}
