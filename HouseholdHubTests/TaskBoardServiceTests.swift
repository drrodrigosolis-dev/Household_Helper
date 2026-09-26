import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct TaskBoardServiceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let container: ModelContainer
        let board: TaskBoardService
        let ledger: TransactionService

        func context() -> ModelContext { ModelContext(container) }

        func columns() throws -> [BoardColumn] {
            try context().fetch(FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)]))
        }

        func task(_ id: UUID) throws -> TaskItem {
            let found = try context().fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id }))
            return try #require(found.first)
        }

        /// Titles of the visible tasks in a column, top to bottom.
        func titles(in columnID: UUID) throws -> [String] {
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.columnID == columnID && $0.archivedAt == nil },
                sortBy: [SortDescriptor(\.sortOrder)])
            return try context().fetch(descriptor).map(\.title)
        }

        func subtaskTitles(of taskID: UUID) throws -> [String] {
            let descriptor = FetchDescriptor<SubtaskItem>(
                predicate: #Predicate { $0.taskID == taskID }, sortBy: [SortDescriptor(\.sortOrder)])
            return try context().fetch(descriptor).map(\.title)
        }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let fixture = Fixture(
            container: container, board: .make(container: container), ledger: .make(container: container))
        try await fixture.board.seedDefaultColumnsIfNeeded(now: now)
        return fixture
    }

    private func add(_ title: String, in column: UUID? = nil, to fixture: Fixture) async throws -> UUID {
        try await fixture.board.createTask(TaskDraft(title: title), in: column, now: now)
    }

    // MARK: Sort keys

    static let sortKeyCases: [(Double?, Double?, Double)] = [
        (nil, nil, 1.0), (3.0, nil, 4.0), (nil, 2.0, 1.0), (1.0, 2.0, 1.5),
    ]

    @Test(arguments: sortKeyCases)
    func sortKeysSplitNeighbours(before: Double?, after: Double?, expected: Double) {
        #expect(SortKey.between(before, after) == expected)
    }

    @Test func sortKeysRefuseGapsTooSmallToSplit() {
        #expect(SortKey.between(1.0, 1.0 + SortKey.minimumGap / 2) == nil)
    }

    // MARK: Columns

    @Test func seedsThreeSystemColumnsOnce() async throws {
        let fixture = try await makeFixture()
        try await fixture.board.seedDefaultColumnsIfNeeded(now: now)
        let columns = try fixture.columns()
        #expect(columns.map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(columns.allSatisfy(\.isSystem))
        #expect(columns.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func newColumnsGoBeforeTheDoneColumn() async throws {
        let fixture = try await makeFixture()
        try await fixture.board.createColumn(named: "  Waiting  ", now: now)
        #expect(try fixture.columns().map(\.name) == ["To Do", "In Progress", "Waiting", "Done"])
        await #expect(throws: TaskBoardError.emptyColumnName) {
            try await fixture.board.createColumn(named: " ", now: now)
        }
    }

    @Test func deletingAColumnMovesItsTasksFirst() async throws {
        let fixture = try await makeFixture()
        let waiting = try await fixture.board.createColumn(named: "Waiting", now: now)
        let todo = try fixture.columns()[0].id
        _ = try await add("Existing", in: todo, to: fixture)
        _ = try await add("Call plumber", in: waiting, to: fixture)
        _ = try await add("Order filter", in: waiting, to: fixture)
        await #expect(throws: TaskBoardError.destinationIsSource) {
            try await fixture.board.deleteColumn(waiting, movingTasksTo: waiting, now: now)
        }
        try await fixture.board.deleteColumn(waiting, movingTasksTo: todo, now: now)
        #expect(try fixture.titles(in: todo) == ["Existing", "Call plumber", "Order filter"])
        #expect(try fixture.columns().map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(try fixture.columns().map(\.sortOrder) == [0, 1, 2])
        #expect(try fixture.context().fetchCount(FetchDescriptor<TaskItem>()) == 3)
    }

    @Test func systemColumnsCannotBeDeleted() async throws {
        let fixture = try await makeFixture()
        let columns = try fixture.columns()
        await #expect(throws: TaskBoardError.systemColumnIsPermanent) {
            try await fixture.board.deleteColumn(columns[0].id, movingTasksTo: columns[1].id, now: now)
        }
        try await fixture.board.renameColumn(columns[0].id, to: "Backlog", now: now)
        #expect(try fixture.columns()[0].name == "Backlog")
    }

    @Test func reorderingColumnsMovesTheDoneMeaning() async throws {
        let fixture = try await makeFixture()
        let columns = try fixture.columns()
        let inDone = try await add("Finished", in: columns[2].id, to: fixture)
        let inProgress = try await add("Working", in: columns[1].id, to: fixture)
        #expect(try fixture.task(inDone).completedAt == now)
        // Move "In Progress" to the end: it becomes the done column.
        try await fixture.board.moveColumn(columns[1].id, to: 2, now: now)
        #expect(try fixture.columns().map(\.name) == ["To Do", "Done", "In Progress"])
        #expect(try fixture.task(inDone).completedAt == nil)
        #expect(try fixture.task(inProgress).completedAt == now)
    }

    // MARK: Tasks

    @Test func tasksAreValidatedAndAppendedToTheFirstColumn() async throws {
        let fixture = try await makeFixture()
        await #expect(throws: TaskBoardError.emptyTitle) {
            try await fixture.board.createTask(TaskDraft(title: "  "), now: now)
        }
        await #expect(throws: TaskBoardError.unknownWishlistItem) {
            try await fixture.board.createTask(TaskDraft(title: "Buy", linkedWishlistItemID: UUID()), now: now)
        }
        let first = try await add("  Water plants ", to: fixture)
        _ = try await add("Take out bins", to: fixture)
        let todo = try fixture.columns()[0].id
        #expect(try fixture.titles(in: todo) == ["Water plants", "Take out bins"])
        #expect(try fixture.task(first).completedAt == nil)
    }

    @Test func movingReordersWithinAndAcrossColumns() async throws {
        let fixture = try await makeFixture()
        let columns = try fixture.columns()
        let todo = columns[0].id
        let a = try await add("A", to: fixture)
        _ = try await add("B", to: fixture)
        let c = try await add("C", to: fixture)
        try await fixture.board.moveTask(c, to: todo, at: 0, now: now)
        #expect(try fixture.titles(in: todo) == ["C", "A", "B"])
        try await fixture.board.moveTask(c, to: todo, at: 2, now: now)
        #expect(try fixture.titles(in: todo) == ["A", "B", "C"])
        try await fixture.board.moveTask(a, to: columns[1].id, at: 0, now: now)
        #expect(try fixture.titles(in: todo) == ["B", "C"])
        #expect(try fixture.titles(in: columns[1].id) == ["A"])
    }

    @Test func repeatedMidpointMovesRenumberInsteadOfLosingOrder() async throws {
        let fixture = try await makeFixture()
        let todo = try fixture.columns()[0].id
        _ = try await add("First", to: fixture)
        _ = try await add("Last", to: fixture)
        var expected = ["First", "Last"]
        // Each new task is squeezed in right after "First", halving the gap every time.
        for index in 0..<60 {
            let id = try await add("T\(index)", to: fixture)
            try await fixture.board.moveTask(id, to: todo, at: 1, now: now)
            expected.insert("T\(index)", at: 1)
        }
        #expect(try fixture.titles(in: todo) == expected)
    }

    @Test func completionFollowsTheDoneColumn() async throws {
        let fixture = try await makeFixture()
        let columns = try fixture.columns()
        let id = try await add("Fix tap", to: fixture)
        try await fixture.board.setTaskCompleted(true, task: id, now: now)
        #expect(try fixture.task(id).columnID == columns[2].id)
        #expect(try fixture.task(id).completedAt == now)
        let later = now.addingTimeInterval(60)
        try await fixture.board.setTaskCompleted(true, task: id, now: later)
        #expect(try fixture.task(id).completedAt == now, "Completing again keeps the original time")
        try await fixture.board.moveTask(id, to: columns[1].id, at: 0, now: later)
        #expect(try fixture.task(id).completedAt == nil)
        try await fixture.board.setTaskCompleted(false, task: id, now: later)
        #expect(try fixture.task(id).columnID == columns[1].id, "Reopening an open task leaves it in place")
        try await fixture.board.moveTask(id, to: columns[2].id, at: 0, now: later)
        try await fixture.board.setTaskCompleted(false, task: id, now: later)
        #expect(try fixture.task(id).columnID == columns[0].id)
        #expect(try fixture.task(id).completedAt == nil)
    }

    @Test func archivedTasksLeaveTheColumnButKeepTheirData() async throws {
        let fixture = try await makeFixture()
        let todo = try fixture.columns()[0].id
        let id = try await add("Old chore", to: fixture)
        try await fixture.board.setTaskArchived(true, task: id, now: now)
        #expect(try fixture.titles(in: todo).isEmpty)
        #expect(try fixture.task(id).archivedAt == now)
        try await fixture.board.setTaskArchived(false, task: id, now: now)
        #expect(try fixture.titles(in: todo) == ["Old chore"])
    }

    @Test func deletingATaskDeletesItsSubtasksOnly() async throws {
        let fixture = try await makeFixture()
        let keep = try await add("Keep", to: fixture)
        let gone = try await add("Gone", to: fixture)
        try await fixture.board.addSubtask(titled: "Keep step", to: keep, now: now)
        try await fixture.board.addSubtask(titled: "Gone step", to: gone, now: now)
        try await fixture.board.deleteTask(gone)
        #expect(try fixture.context().fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try fixture.context().fetch(FetchDescriptor<SubtaskItem>()).map(\.title) == ["Keep step"])
    }

    // MARK: Subtasks

    @Test func subtasksAddToggleRenameReorderAndDelete() async throws {
        let fixture = try await makeFixture()
        let id = try await add("Paint room", to: fixture)
        let tape = try await fixture.board.addSubtask(titled: "Tape edges", to: id, now: now)
        let buy = try await fixture.board.addSubtask(titled: "Buy paint", to: id, now: now)
        await #expect(throws: TaskBoardError.emptyTitle) {
            try await fixture.board.addSubtask(titled: "", to: id, now: now)
        }
        try await fixture.board.moveSubtask(buy, to: 0, now: now)
        #expect(try fixture.subtaskTitles(of: id) == ["Buy paint", "Tape edges"])
        try await fixture.board.setSubtaskCompleted(true, subtask: tape, now: now)
        try await fixture.board.renameSubtask(buy, to: "Buy paint and rollers", now: now)
        try await fixture.board.deleteSubtask(tape)
        #expect(try fixture.subtaskTitles(of: id) == ["Buy paint and rollers"])
    }

    // MARK: Links

    @Test func deletingAWishlistItemClearsTaskLinks() async throws {
        let fixture = try await makeFixture()
        try await fixture.ledger.ensureSettings(currencyCode: "CAD", now: now)
        let draft = WishlistDraft(name: "Lamp", estimatedPrice: Money(minorUnits: 100, currencyCode: "CAD"))
        let item = try await fixture.ledger.createWishlistItem(draft, now: now)
        let linked = TaskDraft(title: "Pick lamp", linkedWishlistItemID: item)
        let task = try await fixture.board.createTask(linked, now: now)
        try await fixture.ledger.deleteWishlistItem(item, now: now)
        #expect(try fixture.task(task).linkedWishlistItemID == nil)
    }
}
