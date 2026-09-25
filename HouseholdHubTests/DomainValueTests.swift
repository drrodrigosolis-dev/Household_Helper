import Foundation
import Testing

@testable import HouseholdHubCore

struct DomainValueTests {
    @Test(arguments: [
        (CategoryKind.expense, TransactionType.expense, true), (.expense, .income, false), (.income, .income, true),
        (.income, .expense, false), (.both, .income, true), (.both, .expense, true), (.both, .transfer, false),
    ])
    func categoryKindGuardsTransactionType(kind: CategoryKind, type: TransactionType, allowed: Bool) {
        #expect(kind.allows(type) == allowed)
    }

    @Test func colorTokenHexRoundTrip() throws {
        let token = try #require(ColorToken(hex: "#1E88E5"))
        #expect(token == ColorToken(red: 0x1E, green: 0x88, blue: 0xE5))
        #expect(token.hex == "#1E88E5FF")
        #expect(ColorToken(hex: "1E88E580")?.alpha == 0x80)
        #expect(ColorToken(hex: "#12345") == nil)
        #expect(ColorToken(hex: "#GGGGGG") == nil)
    }

    @Test func colorTokenContrastMatchesWCAG() {
        #expect(abs(ColorToken.black.contrastRatio(with: .white) - 21) < 0.001)
        #expect(ColorToken.white.contrastRatio(with: .white) == 1)
        let midGray = ColorToken(red: 0x76, green: 0x76, blue: 0x76)
        #expect(midGray.meetsAAContrast(against: .white))
        let lightGray = ColorToken(red: 0x99, green: 0x99, blue: 0x99)
        #expect(!lightGray.meetsAAContrast(against: .white))
        #expect(lightGray.meetsAAContrast(against: .black, largeText: true))
    }

    @Test(arguments: [("  Café  Luna ", "cafe luna"), ("STARBUCKS", "starbucks"), ("Tim\tHortons", "tim hortons")])
    func merchantNamesNormalize(input: String, expected: String) {
        #expect(Merchant.normalize(input) == expected)
    }

    @Test func ledgerLineBalanceEffectSign() throws {
        let amount = Money(minorUnits: 4750, currencyCode: "CAD")
        let now = Date(timeIntervalSince1970: 0)
        let income = LedgerLine(amount: amount, type: .income, status: .posted, occurredAt: now)
        let expense = LedgerLine(amount: amount, type: .expense, status: .posted, occurredAt: now)
        let transfer = LedgerLine(amount: amount, type: .transfer, status: .posted, occurredAt: now)
        #expect(try income.balanceEffect().minorUnits == 4750)
        #expect(try expense.balanceEffect().minorUnits == -4750)
        #expect(try transfer.balanceEffect().isZero)
    }
}
