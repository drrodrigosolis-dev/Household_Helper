import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23 F2: recurring detection from history. Posted expenses and income repeating weekly, every two weeks or
/// monthly, at least three times, with amounts within ±10 % and a recent last one, become suggestions, unless a
/// series already covers the merchant.
struct RecurringDetectorTests {
    private static let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: Self.zone) }
    /// Monday 28 September 2026, noon.
    private var now: Date { Self.date(9, 28, hour: 12) }

    private static func date(_ month: Int, _ day: Int, hour: Int = 10) -> Date {
        var parts = DateComponents(year: 2026, month: month, day: day, hour: hour)
        parts.timeZone = zone
        return HouseholdCalendar(timeZone: zone).calendar.date(from: parts)!
    }

    private static func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private static func history(
        _ days: [(Int, Int)], amounts: [Int64], type: TransactionType = .expense, merchant: String,
        merchantID: UUID? = nil, status: TransactionStatus = .posted, seriesID: UUID? = nil
    ) -> [RecurringHistoryItem] {
        zip(days, amounts).map { day, amount in
            RecurringHistoryItem(
                amount: cad(amount), type: type, status: status, occurredAt: date(day.0, day.1),
                merchantID: merchantID, merchantName: merchant, recurringSeriesID: seriesID)
        }
    }

    // MARK: Fixtures

    struct DetectionCase: Sendable, CustomTestStringConvertible {
        let label: String
        let days: [[Int]]
        let amounts: [Int64]
        let type: TransactionType
        let expectedCadence: RecurringCadence?
        let expectedKind: RecurringKind?
        let expectedRule: RecurrenceRule?
        /// Month and day of the expected next date (a local midnight).
        let expectedNext: [Int]?
        let expectedCount: Int?
        var testDescription: String { label }
    }

    static let detectionCases = [
        DetectionCase(
            label: "weekly groceries become a purchase", days: [[9, 5], [9, 12], [9, 19], [9, 26]],
            amounts: [8_520, 9_110, 8_740, 8_990], type: .expense, expectedCadence: .weekly, expectedKind: .purchase,
            expectedRule: .weekly(interval: 1, weekday: 7), expectedNext: [10, 3], expectedCount: 4),
        DetectionCase(
            label: "monthly streaming becomes a bill", days: [[6, 15], [7, 15], [8, 14], [9, 15]],
            amounts: [1_799, 1_799, 1_799, 1_799], type: .expense, expectedCadence: .monthly, expectedKind: .bill,
            expectedRule: .monthlyOnDay(day: 15), expectedNext: [10, 15], expectedCount: 4),
        DetectionCase(
            label: "a paycheck every two weeks is income", days: [[8, 7], [8, 21], [9, 4], [9, 18]],
            amounts: [250_000, 250_000, 250_000, 250_000], type: .income, expectedCadence: .biweekly,
            expectedKind: .bill, expectedRule: .weekly(interval: 2, weekday: 6), expectedNext: [10, 2],
            expectedCount: 4),
        DetectionCase(
            label: "an older irregular visit is not counted", days: [[7, 2], [9, 12], [9, 19], [9, 26]],
            amounts: [8_000, 8_000, 8_000, 8_000], type: .expense, expectedCadence: .weekly, expectedKind: .purchase,
            expectedRule: .weekly(interval: 1, weekday: 7), expectedNext: [10, 3], expectedCount: 3),
        DetectionCase(
            label: "irregular dates are nothing", days: [[8, 3], [8, 20], [9, 1], [9, 25]],
            amounts: [4_000, 4_000, 4_000, 4_000], type: .expense, expectedCadence: nil, expectedKind: nil,
            expectedRule: nil, expectedNext: nil, expectedCount: nil),
        DetectionCase(
            label: "two occurrences are not enough", days: [[8, 15], [9, 15]], amounts: [1_799, 1_799],
            type: .expense, expectedCadence: nil, expectedKind: nil, expectedRule: nil, expectedNext: nil,
            expectedCount: nil),
        DetectionCase(
            label: "amounts more than 10 % apart are nothing", days: [[7, 15], [8, 15], [9, 15]],
            amounts: [1_799, 2_500, 1_799], type: .expense, expectedCadence: nil, expectedKind: nil,
            expectedRule: nil, expectedNext: nil, expectedCount: nil),
        DetectionCase(
            label: "a pattern that stopped is nothing", days: [[5, 1], [6, 1], [7, 1]],
            amounts: [5_000, 5_000, 5_000], type: .expense, expectedCadence: nil, expectedKind: nil,
            expectedRule: nil, expectedNext: nil, expectedCount: nil),
        DetectionCase(
            label: "a drifting day of the month is nothing", days: [[7, 20], [8, 16], [9, 12]],
            amounts: [5_000, 5_000, 5_000], type: .expense, expectedCadence: nil, expectedKind: nil,
            expectedRule: nil, expectedNext: nil, expectedCount: nil),
    ]

    @Test(arguments: detectionCases)
    func detectsCadenceKindRuleAndNextDate(_ entry: DetectionCase) throws {
        let days = entry.days.map { ($0[0], $0[1]) }
        let items = Self.history(days, amounts: entry.amounts, type: entry.type, merchant: "Streaming Co")
        let found = RecurringDetector().suggestions(from: items, existing: [], now: now, calendar: calendar)
        guard let cadence = entry.expectedCadence else {
            #expect(found.isEmpty)
            return
        }
        let suggestion = try #require(found.first)
        #expect(found.count == 1)
        #expect(suggestion.cadence == cadence)
        #expect(suggestion.kind == entry.expectedKind)
        #expect(suggestion.rule == entry.expectedRule)
        #expect(suggestion.type == entry.type)
        #expect(suggestion.amount == Self.cad(entry.amounts.last ?? 0), "The template is the latest amount")
        #expect(suggestion.occurrenceCount == entry.expectedCount)
        #expect(suggestion.merchantName == "Streaming Co")
        let next = try #require(entry.expectedNext)
        #expect(suggestion.nextDate == calendar.startOfDay(for: Self.date(next[0], next[1])))
    }

    // MARK: Other charges at the same merchant

    struct NoiseCase: Sendable, CustomTestStringConvertible {
        let label: String
        let regularDays: [[Int]]
        let regularAmount: Int64
        let noiseDays: [[Int]]
        let noiseAmounts: [Int64]
        let expectedCadence: RecurringCadence?
        let expectedCount: Int?
        let expectedNext: [Int]?
        var testDescription: String { label }
    }

    static let noiseCases = [
        NoiseCase(
            label: "a monthly subscription among one-off purchases, the latest charge a one-off",
            regularDays: [[6, 15], [7, 15], [8, 15], [9, 15]], regularAmount: 1_799,
            noiseDays: [[6, 20], [7, 2], [8, 1], [8, 28], [9, 20], [9, 27]],
            noiseAmounts: [4_250, 899, 12_000, 2_599, 650, 3_100], expectedCadence: .monthly, expectedCount: 4,
            expectedNext: [10, 15]),
        NoiseCase(
            label: "a one-off on the same day as a monthly charge",
            regularDays: [[7, 15], [8, 15], [9, 15]], regularAmount: 1_799, noiseDays: [[8, 15], [9, 15]],
            noiseAmounts: [5_000, 999], expectedCadence: .monthly, expectedCount: 3, expectedNext: [10, 15]),
        NoiseCase(
            label: "one-offs just outside ±10 % don't break the run",
            regularDays: [[6, 15], [7, 15], [8, 15], [9, 15]], regularAmount: 1_799,
            noiseDays: [[7, 1], [8, 30]], noiseAmounts: [1_619, 1_979], expectedCadence: .monthly,
            expectedCount: 4, expectedNext: [10, 15]),
        NoiseCase(
            label: "a weekly charge among bigger shops",
            regularDays: [[9, 5], [9, 12], [9, 19], [9, 26]], regularAmount: 1_000,
            noiseDays: [[9, 8], [9, 22], [9, 27]], noiseAmounts: [5_000, 7_500, 6_200], expectedCadence: .weekly,
            expectedCount: 4, expectedNext: [10, 3]),
        NoiseCase(
            label: "monthly dates but every amount different is nothing",
            regularDays: [], regularAmount: 0, noiseDays: [[6, 15], [7, 15], [8, 15], [9, 15]],
            noiseAmounts: [1_000, 2_000, 3_000, 4_000], expectedCadence: nil, expectedCount: nil,
            expectedNext: nil),
        NoiseCase(
            label: "only two same-amount charges among the others is nothing",
            regularDays: [[8, 15], [9, 15]], regularAmount: 1_799, noiseDays: [[7, 15], [9, 1]],
            noiseAmounts: [4_000, 2_500], expectedCadence: nil, expectedCount: nil, expectedNext: nil),
        NoiseCase(
            label: "a subscription that stopped is nothing, however recent the other charges",
            regularDays: [[5, 1], [6, 1], [7, 1]], regularAmount: 1_799, noiseDays: [[9, 20], [9, 27]],
            noiseAmounts: [4_000, 2_500], expectedCadence: nil, expectedCount: nil, expectedNext: nil),
    ]

    @Test(arguments: noiseCases)
    func aRegularSameAmountRunIsFoundDespiteOtherChargesAtTheMerchant(_ entry: NoiseCase) throws {
        let merchant = UUID()
        let regular = Self.history(
            entry.regularDays.map { ($0[0], $0[1]) },
            amounts: Array(repeating: entry.regularAmount, count: entry.regularDays.count), merchant: "Streaming Co",
            merchantID: merchant)
        let noise = Self.history(
            entry.noiseDays.map { ($0[0], $0[1]) }, amounts: entry.noiseAmounts, merchant: "Streaming Co",
            merchantID: merchant)
        let found = RecurringDetector().suggestions(from: noise + regular, existing: [], now: now, calendar: calendar)
        guard let cadence = entry.expectedCadence else {
            #expect(found.isEmpty)
            return
        }
        let suggestion = try #require(found.first)
        #expect(found.count == 1, "One suggestion per merchant")
        #expect(suggestion.id == "expense|id:\(merchant.uuidString)", "Dismissals still key on the merchant")
        #expect(suggestion.cadence == cadence)
        #expect(suggestion.amount == Self.cad(entry.regularAmount), "The template is the regular amount")
        #expect(suggestion.occurrenceCount == entry.expectedCount)
        #expect(suggestion.merchantID == merchant)
        let next = try #require(entry.expectedNext)
        #expect(suggestion.nextDate == calendar.startOfDay(for: Self.date(next[0], next[1])))
        let last = try #require(entry.regularDays.last)
        #expect(suggestion.lastDate == Self.date(last[0], last[1]))
    }

    // MARK: Exclusions

    @Test func anExistingSeriesForTheMerchantAndTypeHidesIt() {
        let merchant = UUID()
        let days = [(6, 15), (7, 15), (8, 15), (9, 15)]
        let items = Self.history(
            days, amounts: [1_799, 1_799, 1_799, 1_799], merchant: "Netflix", merchantID: merchant)
        let detector = RecurringDetector()
        let byID = [ExistingSeriesKey(type: .expense, merchantID: merchant, names: ["Movies"])]
        #expect(detector.suggestions(from: items, existing: byID, now: now, calendar: calendar).isEmpty)
        let byName = [ExistingSeriesKey(type: .expense, names: ["  NETFLIX "])]
        #expect(detector.suggestions(from: items, existing: byName, now: now, calendar: calendar).isEmpty)
        let otherType = [ExistingSeriesKey(type: .income, merchantID: merchant, names: ["Netflix"])]
        #expect(detector.suggestions(from: items, existing: otherType, now: now, calendar: calendar).count == 1)
    }

    @Test(arguments: [TransactionType.transfer, .refund])
    func transfersAndRefundsAreNeverSuggested(_ type: TransactionType) {
        let days = [(9, 5), (9, 12), (9, 19), (9, 26)]
        let items = Self.history(days, amounts: [5_000, 5_000, 5_000, 5_000], type: type, merchant: "Bank")
        #expect(RecurringDetector().suggestions(from: items, existing: [], now: now, calendar: calendar).isEmpty)
    }

    @Test(arguments: [TransactionStatus.pending, .cancelled])
    func onlyPostedTransactionsCount(_ status: TransactionStatus) {
        let days = [(9, 5), (9, 12), (9, 19), (9, 26)]
        let items = Self.history(days, amounts: [5_000, 5_000, 5_000, 5_000], merchant: "Deli", status: status)
        #expect(RecurringDetector().suggestions(from: items, existing: [], now: now, calendar: calendar).isEmpty)
    }

    @Test func transactionsPostedFromASeriesAreAlreadyRecurring() {
        let days = [(9, 5), (9, 12), (9, 19), (9, 26)]
        let items = Self.history(days, amounts: [5_000, 5_000, 5_000, 5_000], merchant: "Deli", seriesID: UUID())
        #expect(RecurringDetector().suggestions(from: items, existing: [], now: now, calendar: calendar).isEmpty)
    }

    @Test func namesWithoutAMerchantGroupByTheirNormalizedName() throws {
        let names = ["Streaming Co", "  streaming   CO ", "Stréaming co"]
        let items = zip([(7, 15), (8, 15), (9, 15)], names).map { day, name in
            RecurringHistoryItem(
                amount: Self.cad(1_799), type: .expense, occurredAt: Self.date(day.0, day.1), notes: name)
        }
        let found = RecurringDetector().suggestions(from: items, existing: [], now: now, calendar: calendar)
        let suggestion = try #require(found.first)
        #expect(found.count == 1)
        #expect(suggestion.id == "expense|name:streaming co")
        #expect(suggestion.merchantName == "Stréaming co", "The name shown is the latest one")
    }

    @Test func expenseAndIncomeAtOneMerchantAreSeparate() {
        let days = [(9, 5), (9, 12), (9, 19), (9, 26)]
        let spent = Self.history(days, amounts: [5_000, 5_000, 5_000, 5_000], merchant: "Market")
        let earned = Self.history(days, amounts: [3_000, 3_000, 3_000, 3_000], type: .income, merchant: "Market")
        let found = RecurringDetector().suggestions(from: spent + earned, existing: [], now: now, calendar: calendar)
        #expect(Set(found.map(\.type)) == [.expense, .income])
    }

    @Test(arguments: [
        (1_799 as Int64, 1_799 as Int64, true),
        (1_620, 1_799, true),  // 179 below: 1_790 <= 1_799
        (1_619, 1_799, false),  // 180 below: 1_800 > 1_799
        (1_978, 1_799, true),
        (1_979, 1_799, false),
    ])
    func amountsWithinTenPercentOfTheTemplate(amount: Int64, template: Int64, expected: Bool) {
        let close = RecurringDetector.isClose(Self.cad(amount), to: Self.cad(template))
        #expect(close == expected)
    }

    @Test(arguments: [(15, 15, 0), (14, 17, 3), (30, 1, 2), (31, 1, 1), (1, 28, 4)])
    func dayOfMonthDistanceWrapsAtTheMonthsEnd(first: Int, second: Int, expected: Int) {
        #expect(RecurringDetector.dayDistance(first, second) == expected)
    }

    // MARK: Dismissals

    @Test func dismissedSuggestionsStayHidden() throws {
        let days = [(9, 5), (9, 12), (9, 19), (9, 26)]
        let deli = Self.history(days, amounts: [5_000, 5_000, 5_000, 5_000], merchant: "Deli")
        let market = Self.history(days, amounts: [9_000, 9_000, 9_000, 9_000], merchant: "Market")
        let found = RecurringDetector().suggestions(from: deli + market, existing: [], now: now, calendar: calendar)
        #expect(found.count == 2)
        var dismissals = RecurringSuggestionDismissals()
        dismissals.dismiss(try #require(found.first { $0.merchantName == "Deli" }))
        #expect(dismissals.visible(found).map(\.merchantName) == ["Market"])
        let restored = RecurringSuggestionDismissals(dismissals.stored)
        #expect(restored == dismissals, "Dismissals survive being stored")
    }

    // MARK: Service

    @Test func theServiceFindsHistoryAndStopsOnceASeriesExists() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: Self.cad(100_000), asOf: Self.date(1, 1), now: now)
        for day in [(6, 15), (7, 15), (8, 15), (9, 15)] {
            let draft = TransactionDraft(
                amount: Self.cad(1_799), type: .expense, occurredAt: Self.date(day.0, day.1), merchantName: "Netflix")
            try await ledger.create(draft, now: now)
        }
        let found = try await ledger.recurringSuggestions(now: now, calendar: calendar)
        let suggestion = try #require(found.first)
        #expect(found.count == 1)
        #expect(suggestion.merchantName == "Netflix")
        #expect(suggestion.kind == .bill)
        #expect(suggestion.rule == .monthlyOnDay(day: 15))
        try await ledger.createSeries(
            templateAmount: suggestion.amount, type: .expense, rule: suggestion.rule, timeZone: Self.zone,
            startDate: suggestion.nextDate, notes: "Netflix", now: now)
        #expect(try await ledger.recurringSuggestions(now: now, calendar: calendar).isEmpty)
    }
}
