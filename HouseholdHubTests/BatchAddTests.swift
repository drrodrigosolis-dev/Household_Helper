import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 17: batch add. Lines are read without saving; the batch save is all or nothing.
struct BatchAddTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    /// Sunday 2026-09-27, noon in Vancouver.
    private static let now: Date = {
        let parts = DateComponents(year: 2026, month: 9, day: 27, hour: 12)
        return calendar.calendar.date(from: parts)!
    }()

    private var now: Date { Self.now }
    private let cad = try! Currency(code: "CAD")

    private func day(_ offset: Int) -> Date {
        Self.calendar.startOfDay(for: Self.calendar.calendar.date(byAdding: .day, value: offset, to: Self.now)!)
    }

    // MARK: Task lines

    @Test(arguments: [
        ("call plumber friday", "call plumber", 5),
        ("pay rent tomorrow", "pay rent", 1),
        ("sacar la basura mañana", "sacar la basura", 1),
        ("clean garage sunday", "clean garage", 0),
        ("water plants today", "water plants", 0),
        ("email Sam fri.", "email Sam", 5),
        ("renovar pasaporte miércoles", "renovar pasaporte", 3),
        ("mon standup notes", "standup notes", 1),
    ])
    func taskLineReadsAForwardDueDate(text: String, title: String, daysAhead: Int) {
        let line = TaskLineParser(calendar: Self.calendar).parse(text, now: now)
        #expect(line.title == title)
        #expect(line.dueDate == day(daysAhead))
    }

    @Test(arguments: ["buy 2 lightbulbs", "friday", "fix 3rd step", "read chapter 12"])
    func taskLineKeepsNumbersAndALoneDateWord(text: String) {
        let line = TaskLineParser(calendar: Self.calendar).parse(text, now: now)
        #expect(line.title == text)
        #expect(line.dueDate == nil)
    }

    // MARK: Wishlist lines

    @Test(arguments: [
        ("250 new bike", "new bike", Int64(25_000)),
        ("$1,200 sofa", "sofa", Int64(120_000)),
        ("desk lamp 45.99", "desk lamp", Int64(4_599)),
    ])
    func wishlistLineReadsThePrice(text: String, name: String, minorUnits: Int64) {
        let line = WishlistLineParser(currency: cad, categories: []).parse(text)
        #expect(line.name == name)
        #expect(line.price == Money(minorUnits: minorUnits, currencyCode: "CAD"))
        #expect(!line.priceTooLarge)
    }

    @Test func wishlistLineWithoutAPriceIsUnknownAndATagPicksAnExpenseCategory() {
        let home = QuickAddCategoryOption(id: UUID(), name: "Home", kind: .expense)
        let salary = QuickAddCategoryOption(id: UUID(), name: "Home office income", kind: .income)
        let line = WishlistLineParser(currency: cad, categories: [salary, home]).parse("reading chair #home")
        #expect(line.name == "reading chair")
        #expect(line.price == nil)
        #expect(line.categoryID == home.id)
    }

    @Test(arguments: ["2000000000 yacht", "99999999999999999999999999 boat"])
    func wishlistLineFlagsAnImplausiblePrice(text: String) {
        let line = WishlistLineParser(currency: cad, categories: []).parse(text)
        #expect(line.priceTooLarge)
        #expect(line.price == nil)
    }

    // MARK: Planner

    @Test func plannerStripsListMarkersAndSkipsBlankLines() {
        let text = """
            - buy milk
            * [ ] call plumber friday

            • renew passport
            1. pay rent tomorrow
            2) book dentist
            ☐ fix gate
            """
        let lines = planner(.tasks).plan(text, now: now)
        #expect(lines.map(\.number) == [1, 2, 4, 5, 6, 7])
        #expect(
            lines.taskDrafts.map(\.title) == [
                "buy milk", "call plumber", "renew passport", "pay rent", "book dentist", "fix gate",
            ])
        #expect(lines.taskDrafts[1].dueDate == day(5))
    }

    @Test func plannerSkipsLinesWithNothingLeftAndLinesPastTheLimit() {
        let wishes = planner(.wishlist).plan("250\n#home\nlamp 30", now: now)
        #expect(wishes.map(\.result.skipReason) == [.noText, .noText, nil])
        #expect(wishes.wishlistDrafts.map(\.name) == ["lamp"])

        let many = (1...(BatchAddPlanner.maxItems + 3)).map { "task \($0)" }.joined(separator: "\n")
        let lines = planner(.tasks).plan(many, now: now)
        #expect(lines.taskDrafts.count == BatchAddPlanner.maxItems)
        #expect(lines.suffix(3).allSatisfy { $0.result.skipReason == .overLimit })
    }

    @Test func plannerMakesWishlistDraftsWithUnknownPriceAsZero() throws {
        let lines = planner(.wishlist).plan("headphones\n80 boots", now: now)
        let drafts = lines.wishlistDrafts
        #expect(drafts.map(\.estimatedPrice.minorUnits) == [0, 8_000])
        #expect(drafts.allSatisfy { $0.status == .wanted && $0.priority == .medium })
    }

    private func planner(_ kind: BatchAddKind) -> BatchAddPlanner {
        BatchAddPlanner(kind: kind, currency: cad, categories: [], calendar: Self.calendar)
    }

    // MARK: Batch saves

    private func services() async throws -> (ModelContainer, TaskBoardService, TransactionService) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let board = TaskBoardService.make(container: container)
        let ledger = TransactionService.make(container: container)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        return (container, board, ledger)
    }

    @Test func createTasksAddsEveryTaskToTheFirstColumnInOrder() async throws {
        let (container, board, _) = try await services()
        _ = try await board.createTask(TaskDraft(title: "already there"), now: now)
        let drafts = ["one", "two", "three"].map { TaskDraft(title: $0) }
        let ids = try await board.createTasks(drafts, now: now)
        #expect(ids.count == 3)

        let context = ModelContext(container)
        let first = try #require(
            try context.fetch(FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)])).first)
        let columnID = first.id
        let titles = try context.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.columnID == columnID }, sortBy: [SortDescriptor(\.sortOrder)])
        ).map(\.title)
        #expect(titles == ["already there", "one", "two", "three"])
    }

    @Test func createTasksSavesNothingWhenOneDraftIsInvalid() async throws {
        let (container, board, _) = try await services()
        let drafts = [TaskDraft(title: "fine"), TaskDraft(title: "   "), TaskDraft(title: "also fine")]
        await #expect(throws: TaskBoardError.emptyTitle) {
            try await board.createTasks(drafts, now: now)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TaskItem>()) == 0)
        // The service is still usable afterwards: nothing half-inserted rides along with the next save.
        _ = try await board.createTask(TaskDraft(title: "next"), now: now)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TaskItem>()) == 1)
    }

    @Test func createWishlistItemsKeepsPasteOrderInTheNewestFirstList() async throws {
        let (container, _, ledger) = try await services()
        let drafts = ["bike", "sofa", "lamp"].map {
            WishlistDraft(name: $0, estimatedPrice: Money(minorUnits: 1_000, currencyCode: "CAD"))
        }
        try await ledger.createWishlistItems(drafts, now: now)
        let names = try ModelContext(container).fetch(
            FetchDescriptor<WishlistItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).map(\.name)
        #expect(names == ["bike", "sofa", "lamp"])
    }

    @Test func createWishlistItemsSavesNothingWhenOneDraftIsInvalid() async throws {
        let (container, _, ledger) = try await services()
        let drafts = [
            WishlistDraft(name: "bike", estimatedPrice: Money(minorUnits: 1_000, currencyCode: "CAD")),
            WishlistDraft(name: "euro lamp", estimatedPrice: Money(minorUnits: 1_000, currencyCode: "EUR")),
        ]
        await #expect(throws: (any Error).self) {
            try await ledger.createWishlistItems(drafts, now: now)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WishlistItem>()) == 0)
    }

    @Test func emptyBatchesSaveNothing() async throws {
        let (container, board, ledger) = try await services()
        #expect(try await board.createTasks([], now: now).isEmpty)
        #expect(try await ledger.createWishlistItems([], now: now).isEmpty)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WishlistItem>()) == 0)
    }
}
