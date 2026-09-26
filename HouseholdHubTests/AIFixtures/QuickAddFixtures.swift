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

        var testDescription: String { note }
    }

    static let cases: [Case] = [
        // The parser already read the amount: the model changes nothing.
        Case(
            note: "47.50 coffee", model: QuickAddSuggestion(amount: "99"), amount: nil, income: false, category: nil,
            dayOffset: nil),
        // A written-out amount the parser can't read is taken from the model.
        Case(
            note: "twelve dollars lunch with Sam", model: QuickAddSuggestion(amount: "12", categoryName: "dining"),
            amount: 1_200, income: false, category: "Dining", dayOffset: nil),
        // Grouped thousands are read whole, as the §25 grammar reads them.
        Case(
            note: "twelve hundred for the couch", model: QuickAddSuggestion(amount: "1,200.00"), amount: 120_000,
            income: false, category: nil, dayOffset: nil),
        // More decimals than the currency has, a malformed number, or an absurd amount: rejected, not rounded.
        Case(
            note: "some coffee", model: QuickAddSuggestion(amount: "4.505"), amount: nil, income: false,
            category: nil, dayOffset: nil),
        Case(
            note: "some coffee", model: QuickAddSuggestion(amount: "4,50"), amount: nil, income: false, category: nil,
            dayOffset: nil),
        Case(
            note: "a boat", model: QuickAddSuggestion(amount: "2000000"), amount: nil, income: false, category: nil,
            dayOffset: nil),
        // Income only when the model says so; a category of the wrong kind is dropped.
        Case(
            note: "got paid", model: QuickAddSuggestion(type: "income", categoryName: "Dining"), amount: nil,
            income: true, category: nil, dayOffset: nil),
        // A category that isn't the household's is ignored, and dates stay within the past month.
        Case(
            note: "groceries last week", model: QuickAddSuggestion(categoryName: "Food", dayOffset: -7), amount: nil,
            income: false, category: nil, dayOffset: -7),
        Case(
            note: "rent", model: QuickAddSuggestion(amount: "-5", dayOffset: -400), amount: nil, income: false,
            category: nil, dayOffset: nil),
        Case(
            note: "dentist next week", model: QuickAddSuggestion(dayOffset: 7), amount: nil, income: false,
            category: nil, dayOffset: nil),
        // A day the text named, today included, is never moved.
        Case(
            note: "4.50 coffee today", model: QuickAddSuggestion(dayOffset: -1), amount: nil, income: false,
            category: nil, dayOffset: nil),
        Case(
            note: "4.50 coffee yesterday", model: QuickAddSuggestion(dayOffset: -3), amount: nil, income: false,
            category: nil, dayOffset: nil),
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
    }

    @Test func parserReportsANamedDay() {
        #expect(Self.parse("4.50 coffee today").dateRecognized)
        #expect(Self.parse("4.50 coffee monday").dateRecognized)
        #expect(!Self.parse("4.50 coffee").dateRecognized)
    }

    // MARK: Merging into a form the user may have changed meanwhile

    private static let yesterday = calendar.calendar.date(byAdding: .day, value: -1, to: now)!
    private static let full = ValidatedQuickAdd(
        amount: Money(minorUnits: 1_200, currencyCode: "CAD"), type: .income, categoryID: salary.id,
        occurredAt: yesterday)

    private static func form(
        _ type: TransactionType? = .expense, amountIsEmpty: Bool = true, categoryID: UUID? = nil,
        occurredAt: Date = now
    ) -> QuickAddFormSnapshot {
        QuickAddFormSnapshot(type: type, amountIsEmpty: amountIsEmpty, categoryID: categoryID, occurredAt: occurredAt)
    }

    @Test func mergeFillsAnUntouchedForm() {
        let result = QuickAddSuggestionMerge.fieldsToApply(
            Self.full, form: Self.form(), parsed: Self.parse("got paid"), categories: Self.options)
        #expect(result == Self.full)
    }

    @Test func mergeNeverReplacesWhatTheUserEntered() {
        let picked = Self.calendar.calendar.date(byAdding: .day, value: -3, to: Self.now)!
        let form = Self.form(amountIsEmpty: false, categoryID: Self.dining.id, occurredAt: picked)
        let result = QuickAddSuggestionMerge.fieldsToApply(
            Self.full, form: form, parsed: Self.parse("got paid"), categories: Self.options)
        #expect(result == ValidatedQuickAdd(type: .income))
    }

    @Test func mergeLeavesANamedDayAlone() {
        let parsed = Self.parse("got paid today")
        let result = QuickAddSuggestionMerge.fieldsToApply(
            Self.full, form: Self.form(occurredAt: parsed.occurredAt), parsed: parsed, categories: Self.options)
        #expect(result.occurredAt == nil)
    }

    @Test func mergeChecksTheCategoryAgainstTheSelectedSegment() {
        // The user switched to Income after the model picked an expense category.
        let suggestion = ValidatedQuickAdd(categoryID: Self.dining.id)
        let result = QuickAddSuggestionMerge.fieldsToApply(
            suggestion, form: Self.form(.income), parsed: Self.parse("lunch"), categories: Self.options)
        #expect(result.categoryID == nil)
        // The same pick is kept for an Expense entry.
        let expense = QuickAddSuggestionMerge.fieldsToApply(
            suggestion, form: Self.form(.expense), parsed: Self.parse("lunch"), categories: Self.options)
        #expect(expense.categoryID == Self.dining.id)
    }

    @Test func mergeNeverTouchesWishlistOrTaskEntries() {
        let result = QuickAddSuggestionMerge.fieldsToApply(
            Self.full, form: Self.form(nil), parsed: Self.parse("got paid"), categories: Self.options)
        #expect(result.isEmpty)
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

    @Test func aiCategoryIsRecordedAndClearedWhenTheCategoryChanges() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        let dining = try #require(all.first { $0.name == "Dining" }).id
        let groceries = try #require(all.first { $0.name == "Groceries" }).id
        var draft = TransactionDraft(
            amount: cad(1_000), type: .expense, occurredAt: now, categoryID: dining, isAIClassified: true)
        let id = try await ledger.create(draft, now: now)
        func stored() throws -> Bool {
            let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
            return try #require(records.first { $0.id == id }).isAIClassified
        }
        #expect(try stored())
        // An edit that keeps the category keeps the flag, even from an editor that doesn't know about it.
        draft.isAIClassified = false
        draft.notes = "lunch"
        try await ledger.update(id, with: draft, now: now)
        #expect(try stored())
        // Choosing another category by hand clears it.
        draft.categoryID = groceries
        try await ledger.update(id, with: draft, now: now)
        #expect(try !stored())
        // No category, no AI classification.
        let bare = TransactionDraft(amount: cad(500), type: .expense, occurredAt: now, isAIClassified: true)
        let bareID = try await ledger.create(bare, now: now)
        let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(try #require(records.first { $0.id == bareID }).isAIClassified == false)
    }

    @Test func aiSwitchesRestoreFromBackupsAndOldBackupsLeaveThemOff() async throws {
        let source = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: source)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await ledger.setAI(.categorization, enabled: true, now: now)
        try await ledger.setAI(.naturalLanguage, enabled: true, now: now)
        var backup = try await BackupService.make(container: source).snapshot(now: now, appVersion: "1") { _ in nil }

        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        var settings = try #require(try ModelContext(target).fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.aiCategorizationEnabled && settings.naturalLanguageEnabled && !settings.aiInsightsEnabled)

        // A backup written before these switches existed has no values for them: they come back off.
        backup.settings.aiCategorizationEnabled = nil
        backup.settings.naturalLanguageEnabled = nil
        backup.settings.aiInsightsEnabled = nil
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        settings = try #require(try ModelContext(target).fetch(FetchDescriptor<AppSettings>()).first)
        #expect(!settings.aiCategorizationEnabled && !settings.naturalLanguageEnabled && !settings.aiInsightsEnabled)
    }

    private static let facts = AnalyticsFacts(
        periodTitle: "This month", income: "CA$1,200.00", expense: "CA$497.50", net: "CA$702.50", balance: .surplus,
        topCategories: [NamedFigure(name: "Dining", amount: "CA$47.50")],
        topMerchants: [NamedFigure(name: "7-Eleven", amount: "CA$12.00")])

    @Test func narrativeFiguresAreFilledInByTheApp() {
        let text = NarrativeValidator.validate(
            "You spent {expenses} and kept {net}. Dining took {category1}; 7-Eleven {merchant1}.", facts: Self.facts)
        #expect(text == "You spent CA$497.50 and kept CA$702.50. Dining took CA$47.50; 7-Eleven CA$12.00.")
        // The model never sees the figures themselves.
        let prompt = Self.facts.prompt
        #expect(!prompt.contains("497") && !prompt.contains("1,200") && !prompt.contains("47.50"))
    }

    static let rejectedNarratives = [
        // Any figure the model writes itself, whole, partial, re-signed, or in another currency.
        "You spent CA$200.00 this month.",
        "You spent 200.00 this month.",
        "Your net was -CA$702.50.",
        "You spent US$497.50.",
        "You spent 12 percent more.",
        // Placeholders that aren't in the facts, or malformed ones.
        "Travel took {category2}.",
        "You earned {Income}.",
        "You earned {income.",
        "   ",
        String(repeating: "a", count: 700),
    ]

    @Test(arguments: rejectedNarratives)
    func narrativeRejectsFiguresItWroteItself(_ text: String) {
        #expect(NarrativeValidator.validate(text, facts: Self.facts) == nil)
    }
}
