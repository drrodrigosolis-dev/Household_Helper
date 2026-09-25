import Foundation
import Testing

@testable import HouseholdHubCore

struct QuickAddParserTests {
    private let groceries = QuickAddCategoryOption(id: UUID(), name: "Groceries", kind: .expense)
    private let eatingOut = QuickAddCategoryOption(id: UUID(), name: "Eating Out", kind: .expense)
    private let salary = QuickAddCategoryOption(id: UUID(), name: "Salary", kind: .income)
    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)

    /// Friday 2026-09-25 15:00 in Vancouver.
    private let now = Date(timeIntervalSince1970: 1_790_373_600)

    private var parser: QuickAddParser {
        QuickAddParser(
            currency: try! Currency(code: "CAD"), categories: [groceries, eatingOut, salary], calendar: calendar)
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    @Test func referenceInstantIsFridayAfternoonInVancouver() {
        #expect(calendar.calendar.component(.weekday, from: now) == 6)
        #expect(calendar.calendar.component(.hour, from: now) == 15)
    }

    @Test(arguments: [
        ("47.50 coffee", Int64(4750), TransactionType.expense, "coffee"),
        ("+ 1200 paycheck", 120_000, .income, "paycheck"),
        ("+1200 paycheck", 120_000, .income, "paycheck"),
        ("received 50 from mom", 5000, .income, "from mom"),
        ("1,200.50 rent", 120_050, .expense, "rent"),
        ("$9.99 app store", 999, .expense, "app store"),
        ("paid 3 times 4", 300, .expense, "paid times 4"),
        ("12.345 rounding", 1234, .expense, "rounding"),
        ("  7   spaced   out  ", 700, .expense, "spaced out"),
    ])
    func amountTypeAndDescription(input: String, minorUnits: Int64, type: TransactionType, description: String) {
        let result = parser.parse(input, now: now)
        #expect(result.amount == cad(minorUnits))
        #expect(result.type == type)
        #expect(result.description == description)
        #expect(result.occurredAt == now)
    }

    @Test(arguments: ["coffee", "0 free sample", "abc12 notanumber", "12abc", ""])
    func missingOrZeroAmountLeavesAmountEmptyWithoutFailing(input: String) {
        #expect(parser.parse(input, now: now).amount == nil)
    }

    @Test(arguments: [
        ("18 lunch yesterday", 1), ("18 lunch today", 0), ("12 taxi monday", 4), ("5 snack friday", 0),
        ("5 snack Sat", 6), ("5 snack thursday", 1),
    ])
    func dateWordsMeanRecentLocalDays(input: String, daysBack: Int) {
        let result = parser.parse(input, now: now)
        let expected = calendar.calendar.date(byAdding: .day, value: -daysBack, to: now)
        #expect(result.occurredAt == expected)
        #expect(!result.description.lowercased().contains("yesterday"))
    }

    @Test func tagMatchesCategoryNameCaseInsensitively() {
        let result = parser.parse("32.10 weekly shop #GROC", now: now)
        #expect(result.categoryID == groceries.id)
        #expect(result.description == "weekly shop")
    }

    @Test func tagMatchesAnySubstringOfTheName() {
        #expect(parser.parse("22 pizza #out", now: now).categoryID == eatingOut.id)
    }

    @Test func tagNeverSelectsACategoryOfTheWrongKind() {
        let expense = parser.parse("20 bonus #salary", now: now)
        #expect(expense.type == .expense)
        #expect(expense.categoryID == nil)
        let income = parser.parse("income 100 #sal", now: now)
        #expect(income.type == .income)
        #expect(income.categoryID == salary.id)
    }

    @Test func unmatchedTagIsDroppedNotGuessed() {
        let result = parser.parse("32.10 groceries #food", now: now)
        #expect(result.categoryID == nil)
        #expect(result.description == "groceries")
    }

    @Test func parsingIsFastEnoughForTyping() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<1000 {
                _ = parser.parse("+ 1,200.50 paycheck from work #sal yesterday", now: now)
            }
        }
        #expect(elapsed < .milliseconds(1500), "1000 parses took \(elapsed); budget is 150ms per keystroke")
    }
}
