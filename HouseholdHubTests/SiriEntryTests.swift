import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 25: the Add to Wishlist and Add a Task grammars behind the Siri intents.
struct SiriEntryTests {
    /// Friday 2026-09-25 15:00 in Vancouver.
    static let now = Date(timeIntervalSince1970: 1_790_373_600)

    static func settings(onboarded: Bool = true, currency: String = "CAD") -> SettingsSnapshot {
        SettingsSnapshot(
            currencyCode: currency, onboardingCompleted: onboarded,
            startingBalance: Money(minorUnits: 0, currencyCode: currency), startingBalanceDate: now,
            includePendingInProjection: false)
    }

    struct WishCase: Sendable, CustomTestStringConvertible {
        let text: String
        let name: String
        let minorUnits: Int64?
        var testDescription: String { text }
    }

    static let wishCases = [
        WishCase(text: "headphones for 149", name: "headphones", minorUnits: 14_900),
        WishCase(text: "Headphones for $149.99.", name: "Headphones", minorUnits: 14_999),
        WishCase(text: "headphones for 149 dollars", name: "headphones", minorUnits: 14_900),
        WishCase(text: "new sofa for $1,200.50", name: "new sofa", minorUnits: 120_050),
        WishCase(text: "  rain boots   for 45  ", name: "rain boots", minorUnits: 4_500),
        // Spanish: "por" introduces the price, "dólares" may follow it.
        WishCase(text: "audífonos por 149", name: "audífonos", minorUnits: 14_900),
        WishCase(text: "audífonos por 149 dólares", name: "audífonos", minorUnits: 14_900),
        // No price after a final "for": everything is the name, numbers included.
        WishCase(text: "gift for mom", name: "gift for mom", minorUnits: nil),
        WishCase(text: "iPhone 17", name: "iPhone 17", minorUnits: nil),
        WishCase(text: "lamp for 20 for the hall", name: "lamp for 20 for the hall", minorUnits: nil),
        // A Spanish decimal comma is not the §25 number grammar: it stays in the name for the person to see.
        WishCase(text: "audífonos por 149,99", name: "audífonos por 149,99", minorUnits: nil),
    ]

    @Test(arguments: wishCases)
    func wishlistEntriesSplitNameAndPriceInTheHouseholdCurrency(_ entry: WishCase) throws {
        let draft = try WishlistEntry.draft(text: entry.text, settings: Self.settings())
        #expect(draft.name == entry.name)
        #expect(draft.price == entry.minorUnits.map { Money(minorUnits: $0, currencyCode: "CAD") })
    }

    @Test(arguments: [
        ("", SiriEntryError.emptyText),
        ("   ", SiriEntryError.emptyText),
        ("for 149", SiriEntryError.emptyText),
        ("headphones for 0", SiriEntryError.invalidPrice),
        ("headphones for 1.999", SiriEntryError.invalidPrice),
        ("yacht for 5000000000", SiriEntryError.invalidPrice),
    ])
    func wishlistEntriesWithoutANameOrAValidPriceAreRefused(_ text: String, _ error: SiriEntryError) {
        #expect(throws: error) { try WishlistEntry.draft(text: text, settings: Self.settings()) }
    }

    @Test func nothingIsDraftedBeforeSetup() {
        #expect(throws: SiriEntryError.notSetUp) { try WishlistEntry.draft(text: "headphones", settings: nil) }
        #expect(throws: SiriEntryError.notSetUp) {
            try WishlistEntry.draft(text: "headphones", settings: Self.settings(onboarded: false))
        }
    }

    @Test func aWishlistEntryWithoutAPriceIsStoredWithAnUnknownPrice() throws {
        let entry = try WishlistEntry.draft(text: "gift for mom", settings: Self.settings())
        let draft = entry.wishlistDraft(currencyCode: "CAD")
        #expect(draft.estimatedPrice == .zero("CAD"))
        #expect(draft.status == .wanted)
        try draft.validate()
    }

    @Test(arguments: [
        ("call the plumber", "call the plumber"),
        ("  Buy 2 lightbulbs friday.  ", "Buy 2 lightbulbs friday"),
        ("Llamar al fontanero", "Llamar al fontanero"),
    ])
    func taskEntriesKeepTheWholeTextAsTheTitle(_ text: String, _ title: String) throws {
        let draft = try TaskEntry.draft(text: text)
        #expect(draft.title == title)
        #expect(draft.dueDate == nil)
        #expect(draft.recurrence == nil)
    }

    @Test(arguments: ["", "   ", " . "])
    func emptyTaskEntriesAreRefused(_ text: String) {
        #expect(throws: SiriEntryError.emptyText) { try TaskEntry.draft(text: text) }
    }

    @Test(arguments: [
        ("I spent 40, on groceries yesterday.", "I spent 40 on groceries yesterday"),
        ("¿Headphones for $149.99?", "Headphones for $149.99"),
        ("  a   b  ", "a b"),
    ])
    func dictationPunctuationIsDroppedFromWordEnds(_ text: String, _ expected: String) {
        #expect(SiriText.normalize(text) == expected)
    }

    // MARK: Writes through the services, as the intents make them

    @Test func aWishlistEntryIsStoredOnceThroughTheLedger() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: Self.now, now: Self.now)
        let entry = try WishlistEntry.draft(
            text: "headphones for 149", settings: try await ledger.settingsSnapshot())
        try await ledger.createWishlistItem(entry.wishlistDraft(currencyCode: "CAD"), now: Self.now)
        let items = try ModelContext(container).fetch(FetchDescriptor<WishlistItem>())
        #expect(items.count == 1)
        #expect(items.first?.name == "headphones")
        #expect(items.first?.estimatedPrice == Money(minorUnits: 14_900, currencyCode: "CAD"))
        #expect(try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>()).isEmpty)
    }

    @Test func aTaskEntryGoesToTheFirstColumn() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let board = TaskBoardService.make(container: container)
        try await board.seedDefaultColumnsIfNeeded(now: Self.now)
        let id = try await board.createTask(try TaskEntry.draft(text: "call the plumber"), now: Self.now)
        let context = ModelContext(container)
        let first = try #require(
            try context.fetch(FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)])).first)
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == id })
        #expect(task.columnID == first.id)
        #expect(task.title == "call the plumber")
    }

    @Test func siriContextReadsTheSwitchesAndActiveCategories() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: Self.now, now: Self.now)
        try await categories.seedSystemCategoriesIfNeeded(now: Self.now)
        let before = try await ledger.siriContext()
        #expect(before.settings?.onboardingCompleted == true)
        #expect(before.understandsText && before.suggestsCategories)
        let groceries = try #require(before.categories.first { $0.name == "Groceries" })
        try await categories.setArchived(true, category: groceries.id, now: Self.now)
        try await ledger.setAI(.naturalLanguage, enabled: false, now: Self.now)
        let after = try await ledger.siriContext()
        #expect(!after.understandsText)
        #expect(after.suggestsCategories)
        #expect(!after.categories.contains { $0.id == groceries.id })
        #expect(after.categories.count == before.categories.count - 1)
    }
}

/// A stand-in for the on-device model, so the refinement's validation and fallback run in CI.
struct FakeSiriModel: SiriDraftModel {
    var transactionGuess: SiriTransactionGuess?
    var wishlistGuess: SiriWishlistGuess?
    var delay: Duration?

    struct NoAnswer: Error {}

    func transaction(_ text: String, categoryNames: [String]) async throws -> SiriTransactionGuess {
        if let delay { try await Task.sleep(for: delay) }
        guard let transactionGuess else { throw NoAnswer() }
        return transactionGuess
    }

    func wishlist(_ text: String) async throws -> SiriWishlistGuess {
        if let delay { try await Task.sleep(for: delay) }
        guard let wishlistGuess else { throw NoAnswer() }
        return wishlistGuess
    }
}

/// Sprint 25 owner answer 3: the on-device model's draft is used only when it passes the grammar's own checks;
/// otherwise, and whenever it throws or is late, the deterministic draft is.
struct SiriRefinementTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    private static let now = SiriEntryTests.now
    private static let groceries = QuickAddCategoryOption(id: UUID(), name: "Groceries", kind: .expense)
    private static let salary = QuickAddCategoryOption(id: UUID(), name: "Salary", kind: .income)
    private static let options = [groceries, salary]
    private static let safeway = "I spent 40 on groceries at Safeway yesterday"

    private static func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private static func daysBack(_ days: Int) -> Date {
        calendar.calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private static func guess(
        _ amount: String, kind: String = "expense", merchant: String = "", day: String = "", category: String = ""
    ) -> SiriTransactionGuess {
        SiriTransactionGuess(amount: amount, kind: kind, merchant: merchant, datePhrase: day, category: category)
    }

    private func refine(
        _ text: String, _ model: (any SiriDraftModel)?, timeout: Duration = SiriRefinement.modelTimeout
    ) async throws -> RefinedDraft<TransactionDraft> {
        try await SiriRefinement.transaction(
            text: text, settings: SiriEntryTests.settings(), categories: Self.options, model: model, now: Self.now,
            calendar: Self.calendar, timeout: timeout)
    }

    @Test func aValidModelDraftIsUsedWithItsMerchantDayAndCategory() async throws {
        let model = FakeSiriModel(
            transactionGuess: Self.guess("40", merchant: "Safeway", day: "yesterday", category: "groceries"))
        let refined = try await refine(Self.safeway, model)
        #expect(refined.fromModel)
        #expect(refined.draft.amount == Self.cad(4_000))
        #expect(refined.draft.type == .expense)
        #expect(refined.draft.merchantName == "Safeway")
        #expect(refined.draft.categoryID == Self.groceries.id)
        #expect(refined.draft.isAIClassified)
        #expect(refined.draft.occurredAt == Self.daysBack(1))
        #expect(refined.draft.source == .shortcut)
    }

    @Test func theModelMayChooseAnotherNumberThePersonSaid() async throws {
        let model = FakeSiriModel(transactionGuess: Self.guess("9.50", merchant: "coffees"))
        let refined = try await refine("2 coffees for 9.50", model)
        #expect(refined.fromModel)
        #expect(refined.draft.amount == Self.cad(950))
    }

    struct Rejected: Sendable, CustomTestStringConvertible {
        let why: String
        let guess: SiriTransactionGuess?
        var testDescription: String { why }
    }

    static let rejected = [
        Rejected(why: "no answer", guess: nil),
        Rejected(why: "invented amount", guess: guess("45", merchant: "Safeway")),
        Rejected(why: "amount with extra decimals", guess: guess("40.001")),
        Rejected(why: "negative amount", guess: guess("-40")),
        Rejected(why: "empty amount", guess: guess("")),
        Rejected(why: "unknown kind", guess: guess("40", kind: "transfer")),
    ]

    @Test(arguments: rejected)
    func anyInvalidOrMissingAnswerFallsBackToTheGrammar(_ entry: Rejected) async throws {
        let refined = try await refine(Self.safeway, FakeSiriModel(transactionGuess: entry.guess))
        let grammar = try ShortcutEntry.draft(
            text: Self.safeway, settings: SiriEntryTests.settings(), now: Self.now, calendar: Self.calendar)
        #expect(!refined.fromModel)
        #expect(refined.draft == grammar)
        #expect(refined.draft.amount == Self.cad(4_000))
        #expect(refined.draft.occurredAt == Self.daysBack(1))
    }

    @Test func withoutAModelTheGrammarDecides() async throws {
        let refined = try await refine("47.50 coffee.", nil)
        #expect(!refined.fromModel)
        #expect(refined.draft.amount == Self.cad(4_750))
        #expect(refined.draft.merchantName == "coffee")
    }

    @Test func aLateAnswerIsAbandoned() async throws {
        let model = FakeSiriModel(transactionGuess: Self.guess("40"), delay: .seconds(30))
        let started = ContinuousClock.now
        let refined = try await refine(Self.safeway, model, timeout: .milliseconds(50))
        #expect(!refined.fromModel)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func unknownOrWrongKindCategoriesAreDroppedNotGuessed() async throws {
        for name in ["Food", "Salary"] {
            let model = FakeSiriModel(transactionGuess: Self.guess("40", category: name))
            let refined = try await refine(Self.safeway, model)
            #expect(refined.fromModel)
            #expect(refined.draft.categoryID == nil)
            #expect(!refined.draft.isAIClassified)
        }
    }

    @Test func anInventedMerchantFallsBackToTheSentencesWords() async throws {
        let model = FakeSiriModel(transactionGuess: Self.guess("40", merchant: "Costco"))
        let refined = try await refine(Self.safeway, model)
        #expect(refined.fromModel)
        #expect(refined.draft.merchantName == "I spent on groceries at Safeway")
    }

    struct DayCase: Sendable, CustomTestStringConvertible {
        let note: String
        let phrase: String
        let daysBack: Int
        var testDescription: String { "\(note) / \(phrase)" }
    }

    /// Friday: Monday is 4 days back, Wednesday 2.
    static let dayCases = [
        // The model may pick which day the person named.
        DayCase(note: "paid 40 monday for dinner wednesday", phrase: "wednesday", daysBack: 2),
        DayCase(note: "paid 40 monday for dinner wednesday", phrase: "monday", daysBack: 4),
        DayCase(note: "paid 40 monday for dinner wednesday", phrase: "", daysBack: 4),
        DayCase(note: "40 comida ayer", phrase: "ayer", daysBack: 1),
        // A day the sentence doesn't name, or one the day words don't read, is ignored: never a future date.
        DayCase(note: "40 at Safeway", phrase: "yesterday", daysBack: 0),
        DayCase(note: "40 at Safeway tomorrow", phrase: "tomorrow", daysBack: 0),
        DayCase(note: "40 at Safeway next week", phrase: "next week", daysBack: 0),
        DayCase(note: safeway, phrase: "wednesday", daysBack: 1),
    ]

    @Test(arguments: dayCases)
    func theDayComesFromTheSentencesDayWordsAndIsNeverInTheFuture(_ entry: DayCase) async throws {
        let refined = try await refine(entry.note, FakeSiriModel(transactionGuess: Self.guess("40", day: entry.phrase)))
        #expect(refined.fromModel)
        #expect(refined.draft.occurredAt == Self.daysBack(entry.daysBack))
        #expect(refined.draft.occurredAt <= Self.now)
    }

    @Test func incomeComesFromTheModelOrTheSentencesSign() async throws {
        let paid = try await refine(
            "got paid 1200", FakeSiriModel(transactionGuess: Self.guess("1200", kind: "income")))
        #expect(paid.fromModel && paid.draft.type == .income)
        let signed = try await refine("+ 50 refund", FakeSiriModel(transactionGuess: Self.guess("50")))
        #expect(signed.fromModel && signed.draft.type == .income)
    }

    @Test func nothingIsDraftedWithoutAnAmountOrBeforeSetup() async throws {
        await #expect(throws: ShortcutEntryError.noAmount) {
            try await refine("groceries at Safeway", FakeSiriModel(transactionGuess: Self.guess("40")))
        }
        await #expect(throws: ShortcutEntryError.notSetUp) {
            try await SiriRefinement.transaction(
                text: Self.safeway, settings: nil, categories: Self.options,
                model: FakeSiriModel(transactionGuess: Self.guess("40")), now: Self.now, calendar: Self.calendar)
        }
    }

    // MARK: Wishlist

    private func refineWish(
        _ text: String, _ guess: SiriWishlistGuess?
    ) async throws -> RefinedDraft<WishlistEntryDraft> {
        try await SiriRefinement.wishlist(
            text: text, settings: SiriEntryTests.settings(), model: FakeSiriModel(wishlistGuess: guess))
    }

    @Test func aValidWishlistAnswerIsUsed() async throws {
        let text = "I'd love the Sony headphones, they cost 149"
        let refined = try await refineWish(text, SiriWishlistGuess(name: "Sony headphones", price: "149"))
        #expect(refined.fromModel)
        #expect(refined.draft == WishlistEntryDraft(name: "Sony headphones", price: Self.cad(14_900)))
        let unpriced = try await refineWish("a new iPhone 17", SiriWishlistGuess(name: "iPhone 17", price: ""))
        #expect(unpriced.fromModel)
        #expect(unpriced.draft == WishlistEntryDraft(name: "iPhone 17", price: nil))
    }

    @Test(arguments: [
        SiriWishlistGuess(name: "headphones", price: "150"),
        SiriWishlistGuess(name: "Bose speakers", price: "149"),
        SiriWishlistGuess(name: "", price: "149"),
        SiriWishlistGuess(name: "headphones\u{202E}", price: "149"),
        SiriWishlistGuess(name: "headphones", price: "0"),
    ])
    func anInvalidWishlistAnswerFallsBackToTheGrammar(_ guess: SiriWishlistGuess) async throws {
        let refined = try await refineWish("headphones for 149.", guess)
        #expect(!refined.fromModel)
        #expect(refined.draft == WishlistEntryDraft(name: "headphones", price: Self.cad(14_900)))
    }

    @Test func withoutAModelTheWishlistGrammarDecides() async throws {
        let refined = try await SiriRefinement.wishlist(
            text: "audífonos por 149", settings: SiriEntryTests.settings(), model: nil)
        #expect(!refined.fromModel)
        #expect(refined.draft == WishlistEntryDraft(name: "audífonos", price: Self.cad(14_900)))
        await #expect(throws: SiriEntryError.emptyText) {
            try await SiriRefinement.wishlist(
                text: " . ", settings: SiriEntryTests.settings(), model: FakeSiriModel(wishlistGuess: nil))
        }
    }
}
