import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// AI regression fixtures (spec §12.4). Each case: the note, what a model might answer, and what the validators
/// must let through. The validator cases always run; the live cases run only where Apple Intelligence is available
/// (never in CI, whose simulator has no model) and check that answers stay within the allowed alternatives.
struct QuickAddFixtures {
    private static let zone = TimeZone(identifier: "America/Vancouver")!
    private static let calendar = HouseholdCalendar(timeZone: zone)
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let dining = QuickAddCategoryOption(id: UUID(), name: "Dining", kind: .expense)
    private static let salary = QuickAddCategoryOption(id: UUID(), name: "Salary", kind: .income)
    private static let options = [dining, salary]
    private static let currency = try! Currency(code: "CAD")

    private static func parse(_ text: String) -> QuickAddParse {
        QuickAddParser(currency: currency, categories: options, calendar: calendar).parse(text, now: now)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let note: String
        let model: QuickAddSuggestion
        let amount: Int64?
        let income: Bool
        let category: String?
        let dayOffset: Int?
        let description: String?

        var testDescription: String { note }
    }

    static let cases: [Case] = [
        // The parser already read the amount and description: the model changes nothing.
        Case(
            note: "47.50 coffee", model: QuickAddSuggestion(amount: 99, description: "tea"), amount: nil,
            income: false, category: nil, dayOffset: nil, description: nil),
        // A written-out amount the parser can't read is taken from the model.
        Case(
            note: "twelve dollars lunch with Sam", model: QuickAddSuggestion(amount: 12, categoryName: "dining"),
            amount: 1_200, income: false, category: "Dining", dayOffset: nil, description: nil),
        // Income only when the model says so; a category of the wrong kind is dropped.
        Case(
            note: "got paid", model: QuickAddSuggestion(type: "income", categoryName: "Dining"), amount: nil,
            income: true, category: nil, dayOffset: nil, description: nil),
        // A category that isn't the household's is ignored, and dates stay within a month.
        Case(
            note: "groceries last week", model: QuickAddSuggestion(categoryName: "Food", dayOffset: -7), amount: nil,
            income: false, category: nil, dayOffset: -7, description: nil),
        Case(
            note: "rent", model: QuickAddSuggestion(amount: -5, dayOffset: -400), amount: nil, income: false,
            category: nil, dayOffset: nil, description: nil),
    ]

    @Test(arguments: cases)
    func validatorKeepsOnlyAllowedValues(_ fixture: Case) throws {
        let parsed = Self.parse(fixture.note)
        let result = QuickAddSuggestionValidator.validate(
            fixture.model, parsed: parsed, currency: Self.currency, categories: Self.options, now: Self.now,
            calendar: Self.calendar)
        #expect(result.amount?.minorUnits == fixture.amount)
        #expect((result.type == .income) == fixture.income)
        let expectedCategory = Self.options.first(where: { $0.name == fixture.category })?.id
        #expect(result.categoryID == expectedCategory)
        let expectedDate = fixture.dayOffset.flatMap {
            Self.calendar.calendar.date(byAdding: .day, value: $0, to: Self.now)
        }
        #expect(result.occurredAt == expectedDate)
        #expect(result.description == fixture.description)
    }

    @Test(.enabled(if: OnDeviceModel.isAvailable), arguments: cases)
    func liveModelStaysWithinTheValidators(_ fixture: Case) async throws {
        let answer = await OnDeviceModel.suggestQuickAdd(fixture.note, categoryNames: ["Dining", "Salary"])
        let raw = try #require(answer)
        let result = QuickAddSuggestionValidator.validate(
            raw, parsed: Self.parse(fixture.note), currency: Self.currency, categories: Self.options, now: Self.now,
            calendar: Self.calendar)
        // Whatever the model says, the validated result never overrides the parse and never invents a category.
        let parsed = Self.parse(fixture.note)
        if parsed.amount != nil {
            #expect(result.amount == nil)
        }
        if let category = result.categoryID {
            #expect(Self.options.contains { $0.id == category })
        }
    }
}

struct IntelligenceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    @Test func merchantHistorySuggestsTheMostUsedActiveCategory() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        let dining = try #require(all.first { $0.name == "Dining" }).id
        let groceries = try #require(all.first { $0.name == "Groceries" }).id
        for (category, offset) in [(dining, 1), (dining, 2), (groceries, 3)] {
            let draft = TransactionDraft(
                amount: cad(1_000), type: .expense, occurredAt: now.addingTimeInterval(-Double(offset) * 86_400),
                categoryID: category, merchantName: "Café Luna")
            try await ledger.create(draft, now: now)
        }
        #expect(try await ledger.suggestedCategory(forMerchantText: "  cafe LUNA ", type: .expense) == dining)
        #expect(try await ledger.suggestedCategory(forMerchantText: "Unknown", type: .expense) == nil)
        #expect(try await ledger.suggestedCategory(forMerchantText: "Café Luna", type: .income) == nil)
        try await categories.setArchived(true, category: dining, now: now)
        #expect(try await ledger.suggestedCategory(forMerchantText: "Café Luna", type: .expense) == groceries)
    }

    @Test func aiSwitchesStartOffAndRoundTripThroughBackups() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let settings = try #require(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        #expect(!settings.aiCategorizationEnabled && !settings.naturalLanguageEnabled && !settings.aiInsightsEnabled)
        try await ledger.setAI(.insights, enabled: true, now: now)
        let backup = try await BackupService.make(container: container).snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.settings.aiInsightsEnabled == true)
        #expect(backup.settings.naturalLanguageEnabled == false)
    }

    @Test func narrativeMayOnlyQuoteGivenFigures() {
        let facts = AnalyticsFacts(
            periodTitle: "This month", income: "CA$1,200.00", expense: "CA$497.50", net: "CA$702.50",
            topCategories: ["Dining CA$47.50"], topMerchants: [])
        #expect(NarrativeValidator.validate("You spent CA$497.50 and kept CA$702.50.", facts: facts) != nil)
        #expect(NarrativeValidator.validate("You spent CA$510.00 this month.", facts: facts) == nil)
        #expect(NarrativeValidator.validate(String(repeating: "a", count: 700), facts: facts) == nil)
        #expect(NarrativeValidator.validate("   ", facts: facts) == nil)
    }
}
