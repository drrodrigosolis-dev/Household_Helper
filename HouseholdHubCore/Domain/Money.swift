import Foundation

public enum MoneyError: Error, Equatable, Sendable {
    case invalidCurrencyCode(String)
    case currencyMismatch(String, String)
    case overflow
    case notFinite
    /// Division needs a positive number of parts and, here, a non-negative amount.
    case invalidDivision
}

/// Canonical money value: integer minor units plus an ISO currency code (spec §6.1). All accounting arithmetic
/// lives here and is overflow-checked; `Double` is never used.
public struct Money: Hashable, Sendable, Codable {
    public let minorUnits: Int64
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    /// Converts a user-entered decimal amount (e.g. 47.50) into minor units, rounding to the currency's precision.
    public init(decimal: Decimal, currency: Currency, rounding: NSDecimalNumber.RoundingMode = .bankers) throws {
        guard decimal.isFinite else { throw MoneyError.notFinite }
        let minor = try Money.roundedInteger(decimal * Money.scale(currency.minorUnitDigits), rounding: rounding)
        self.init(minorUnits: minor, currencyCode: currency.code)
    }

    /// Largest budget limit or goal target the app accepts or restores: one billion in major units of a two-decimal
    /// currency. It keeps rollover and goal sums far from overflow, and the services and the backup validator share
    /// it, so the app never stores a plan its own export would refuse.
    public static let maxPlanMinorUnits: Int64 = 100_000_000_000

    public static func zero(_ currencyCode: String) -> Money {
        Money(minorUnits: 0, currencyCode: currencyCode)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }

    /// Exact value in major units (4750 CAD minor units → 47.5).
    public var decimalValue: Decimal {
        Decimal(minorUnits) / Money.scale(Currency.minorUnitDigits(forCode: currencyCode))
    }

    // MARK: Arithmetic

    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (result, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: result, currencyCode: currencyCode)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        let (result, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: result, currencyCode: currencyCode)
    }

    public func negated() throws -> Money {
        guard minorUnits != .min else { throw MoneyError.overflow }
        return Money(minorUnits: -minorUnits, currencyCode: currencyCode)
    }

    public func compare(_ other: Money) throws -> ComparisonResult {
        try requireSameCurrency(other)
        if minorUnits < other.minorUnits { return .orderedAscending }
        if minorUnits > other.minorUnits { return .orderedDescending }
        return .orderedSame
    }

    public static func sum(_ values: [Money], currencyCode: String) throws -> Money {
        try values.reduce(zero(currencyCode)) { try $0.adding($1) }
    }

    /// This amount split into `parts` equal shares, rounded up to the minor unit, so paying one share per part never
    /// falls short of the total. The amount must not be negative (rounding up has no meaning for a debt here).
    public func dividedRoundingUp(by parts: Int) throws -> Money {
        guard parts > 0, minorUnits >= 0 else { throw MoneyError.invalidDivision }
        let (quotient, remainder) = minorUnits.quotientAndRemainder(dividingBy: Int64(parts))
        // quotient <= Int64.max / 2 whenever remainder > 0 (parts >= 2), so the + 1 can't overflow.
        return Money(minorUnits: remainder > 0 ? quotient + 1 : quotient, currencyCode: currencyCode)
    }

    /// Mean rounded to the nearest minor unit with banker's rounding; nil for an empty list.
    public static func average(_ values: [Money], currencyCode: String) throws -> Money? {
        guard !values.isEmpty else { return nil }
        let total = try sum(values, currencyCode: currencyCode)
        let mean = try roundedInteger(Decimal(total.minorUnits) / Decimal(values.count), rounding: .bankers)
        return Money(minorUnits: mean, currencyCode: currencyCode)
    }

    /// `part` as a percentage of `whole` (25 means 25%); nil when `whole` is zero.
    public static func percentage(_ part: Money, of whole: Money) throws -> Decimal? {
        try part.requireSameCurrency(whole)
        guard whole.minorUnits != 0 else { return nil }
        return Decimal(part.minorUnits) / Decimal(whole.minorUnits) * 100
    }

    /// Value rounded to whole major units for compact display (charts, summaries); stored values are never rounded.
    public func roundedForDisplay() throws -> Decimal {
        let digits = Currency.minorUnitDigits(forCode: currencyCode)
        let whole = try Money.roundedInteger(Decimal(minorUnits) / Money.scale(digits), rounding: .bankers)
        return Decimal(whole)
    }

    /// Locale-aware currency string; the symbol comes from the currency code at presentation time (spec §6.2).
    public func formatted(locale: Locale = .current) -> String {
        decimalValue.formatted(.currency(code: currencyCode).locale(locale))
    }

    // MARK: Helpers

    private func requireSameCurrency(_ other: Money) throws {
        guard currencyCode == other.currencyCode else {
            throw MoneyError.currencyMismatch(currencyCode, other.currencyCode)
        }
    }

    static func scale(_ digits: Int) -> Decimal {
        pow(Decimal(10), digits)
    }

    static func roundedInteger(_ value: Decimal, rounding: NSDecimalNumber.RoundingMode) throws -> Int64 {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, rounding)
        guard result >= Decimal(Int64.min), result <= Decimal(Int64.max), let int = Int64(result.description) else {
            throw MoneyError.overflow
        }
        return int
    }
}
