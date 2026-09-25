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
    static func parseAmount(_ text: String, currencyCode: String) -> Money? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let currency = try? Currency(code: currencyCode),
            let value = try? Decimal(trimmed, format: .number.locale(.current)),
            let money = try? Money(decimal: value, currency: currency), money.minorUnits > 0
        else { return nil }
        return money
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

extension Color {
    init(_ token: ColorToken) {
        self.init(
            .sRGB, red: Double(token.red) / 255, green: Double(token.green) / 255, blue: Double(token.blue) / 255,
            opacity: Double(token.alpha) / 255)
    }
}

/// Category icon on its color. Decorative: rows describe the category in text for VoiceOver.
struct CategoryBadge: View {
    let icon: String
    let color: ColorToken?

    var body: some View {
        Image(systemName: icon)
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(color.map { Color($0) } ?? Color.gray))
            .accessibilityHidden(true)
    }
}
