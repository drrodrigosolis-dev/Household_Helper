import Foundation

/// A validated ISO 4217 currency with its minor-unit precision (spec §6.2). Symbols are never stored.
public struct Currency: Hashable, Sendable, Codable {
    public let code: String

    public init(code: String) throws {
        let upper = code.uppercased()
        guard upper.count == 3, Locale.commonISOCurrencyCodes.contains(upper) else {
            throw MoneyError.invalidCurrencyCode(code)
        }
        self.code = upper
    }

    public var minorUnitDigits: Int { Currency.minorUnitDigits(forCode: code) }

    /// ISO 4217 exponents. A fixed table rather than ICU data, which differs by OS version and uses cash digits.
    public static func minorUnitDigits(forCode code: String) -> Int {
        if zeroDigitCodes.contains(code) { return 0 }
        if threeDigitCodes.contains(code) { return 3 }
        if fourDigitCodes.contains(code) { return 4 }
        return 2
    }

    private static let zeroDigitCodes = codes("BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF")
    private static let threeDigitCodes = codes("BHD IQD JOD KWD LYD OMR TND")
    private static let fourDigitCodes = codes("CLF UYW")

    private static func codes(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }
}
