import Foundation
import Testing

@testable import HouseholdHubCore

struct MoneyTests {
    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test(arguments: [
        ("47.50", Int64(4750)), ("1000", 100_000), ("1,000.00", 100_000), ("-12.99", -1299), ("0.005", 0),
        ("0.015", 2), ("0.025", 2), ("-0.035", -4),
    ])
    func decimalInputRoundsToMinorUnitsWithBankersRounding(input: String, expected: Int64) throws {
        let text = input.replacingOccurrences(of: ",", with: "")
        let money = try Money(decimal: decimal(text), currency: Currency(code: "CAD"))
        #expect(money == cad(expected))
    }

    @Test(arguments: [("JPY", "1235", Int64(1235)), ("JPY", "12.5", 12), ("KWD", "1.2345", 1234), ("CAD", "1", 100)])
    func currencyPrecisionDrivesScaling(code: String, input: String, expected: Int64) throws {
        let money = try Money(decimal: decimal(input), currency: Currency(code: code))
        #expect(money.minorUnits == expected)
        #expect(money.currencyCode == code)
    }

    @Test func largestValueRoundTripsAndBeyondThrows() throws {
        let currency = try Currency(code: "CAD")
        let max = try Money(decimal: Decimal(Int64.max) / 100, currency: currency)
        #expect(max.minorUnits == .max)
        #expect(throws: MoneyError.overflow) { try Money(decimal: Decimal(Int64.max), currency: currency) }
        #expect(throws: MoneyError.notFinite) { try Money(decimal: .nan, currency: currency) }
    }

    @Test func arithmeticIsCheckedForOverflow() throws {
        #expect(throws: MoneyError.overflow) { try cad(.max).adding(cad(1)) }
        #expect(throws: MoneyError.overflow) { try cad(.min).subtracting(cad(1)) }
        #expect(throws: MoneyError.overflow) { try cad(.min).negated() }
        #expect(try cad(4750).adding(cad(-1299)) == cad(3451))
        #expect(try cad(4750).subtracting(cad(5000)) == cad(-250))
        #expect(try cad(-1299).negated() == cad(1299))
    }

    @Test func mixingCurrenciesThrows() {
        let usd = Money(minorUnits: 100, currencyCode: "USD")
        #expect(throws: MoneyError.currencyMismatch("CAD", "USD")) { try cad(100).adding(usd) }
        #expect(throws: MoneyError.currencyMismatch("CAD", "USD")) { try cad(100).compare(usd) }
        #expect(throws: MoneyError.currencyMismatch("CAD", "USD")) { try Money.sum([usd], currencyCode: "CAD") }
    }

    @Test func sumAverageAndPercentage() throws {
        #expect(try Money.sum([cad(4750), cad(-1299), cad(100_000)], currencyCode: "CAD") == cad(103_451))
        #expect(try Money.sum([], currencyCode: "CAD") == .zero("CAD"))
        #expect(try Money.average([cad(100), cad(101)], currencyCode: "CAD") == cad(100))
        #expect(try Money.average([cad(101), cad(102)], currencyCode: "CAD") == cad(102))
        #expect(try Money.average([], currencyCode: "CAD") == nil)
        #expect(try Money.percentage(cad(25), of: cad(100)) == 25)
        #expect(try Money.percentage(cad(-50), of: cad(200)) == -25)
        #expect(try Money.percentage(cad(5), of: cad(0)) == nil)
    }

    @Test func compareAndPredicates() throws {
        #expect(try cad(1).compare(cad(2)) == .orderedAscending)
        #expect(try cad(2).compare(cad(1)) == .orderedDescending)
        #expect(try cad(2).compare(cad(2)) == .orderedSame)
        #expect(cad(0).isZero)
        #expect(cad(-1).isNegative)
        #expect(!cad(1).isNegative)
    }

    @Test func decimalValueAndDisplayRounding() throws {
        #expect(cad(4750).decimalValue == Decimal(string: "47.5"))
        #expect(Money(minorUnits: 1235, currencyCode: "JPY").decimalValue == 1235)
        #expect(try cad(4750).roundedForDisplay() == 48)
        #expect(try cad(4650).roundedForDisplay() == 46)
    }

    @Test(arguments: [
        (Int64(4750), "USD", "$47.50"), (-1299, "USD", "-$12.99"), (1235, "JPY", "¥1,235"),
        (100_000, "USD", "$1,000.00"),
    ])
    func formattingUsesCurrencyAndLocale(minorUnits: Int64, code: String, expected: String) {
        let money = Money(minorUnits: minorUnits, currencyCode: code)
        #expect(money.formatted(locale: Locale(identifier: "en_US")) == expected)
    }

    @Test func currencyValidation() throws {
        #expect(try Currency(code: "cad").code == "CAD")
        #expect(throws: MoneyError.invalidCurrencyCode("CADX")) { try Currency(code: "CADX") }
        #expect(throws: MoneyError.invalidCurrencyCode("ZZZ")) { try Currency(code: "ZZZ") }
        #expect(try Currency(code: "JPY").minorUnitDigits == 0)
        #expect(try Currency(code: "KWD").minorUnitDigits == 3)
        #expect(try Currency(code: "CAD").minorUnitDigits == 2)
    }
}
