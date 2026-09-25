import Foundation
import Testing

@testable import HouseholdHub

struct LedgerFormatTests {
    @Test(arguments: [
        ("1250.50", "en_US", "1250.5"), ("1,250.50", "en_US", "1250.5"), ("-40", "en_US", "-40"),
        ("1.250,50", "de_DE", "1250.5"), ("1250,50", "de_DE", "1250.5"), ("1\u{202F}250,50", "fr_FR", "1250.5"),
        ("0", "en_US", "0"),
    ])
    func parsesWholeInputInTheUsersLocale(input: String, locale: String, expected: String) throws {
        let value = LedgerFormat.parseDecimal(input, locale: Locale(identifier: locale))
        #expect(value == Decimal(string: expected, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test(arguments: [
        ("12,5", "en_US"), ("1,25.50", "en_US"), ("1250.50abc", "en_US"), ("abc", "en_US"), ("", "en_US"),
        ("12.5", "de_DE"), ("1.2.3", "en_US"),
    ])
    func rejectsAnythingThatIsNotAWholeNumberInsteadOfParsingAPrefix(input: String, locale: String) {
        #expect(LedgerFormat.parseDecimal(input, locale: Locale(identifier: locale)) == nil)
    }

    @Test func amountsMustBePositive() {
        let locale = Locale(identifier: "en_US")
        #expect(LedgerFormat.parseAmount("0", currencyCode: "CAD", locale: locale) == nil)
        #expect(LedgerFormat.parseAmount("-5", currencyCode: "CAD", locale: locale) == nil)
        let money = LedgerFormat.parseAmount("47.50", currencyCode: "CAD", locale: locale)
        #expect(money?.minorUnits == 4750)
    }
}
