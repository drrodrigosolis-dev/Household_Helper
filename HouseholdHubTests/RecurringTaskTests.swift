import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 13: recurring tasks (owner decision 20). Completing a repeating task adds the next one, due on the rule's
/// next date after the completed one's due date, in the column it came from; the completed one keeps no rule.
struct RecurringTaskTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let noon = calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        return calendar.startOfDay(for: noon ?? .distantPast)
    }

    // MARK: Rules

    @Test func repeatChoicesReadTheirDayOffTheDueDate() {
        let friday = day(2026, 9, 25)
        #expect(TaskRepeat.daily.rule(dueDate: friday, calendar: calendar) == .daily(interval: 1))
        #expect(TaskRepeat.weekly.rule(dueDate: friday, calendar: calendar) == .weekly(interval: 1, weekday: 6))
        #expect(TaskRepeat.everyTwoWeeks.rule(dueDate: friday, calendar: calendar) == .weekly(interval: 2, weekday: 6))
        #expect(TaskRepeat.monthly.rule(dueDate: friday, calendar: calendar) == .monthlyOnDay(day: 25))
        #expect(TaskRepeat.yearly.rule(dueDate: friday, calendar: calendar) == .yearly(month: 9, day: 25))
        for choice in TaskRepeat.allCases {
            let rule = choice.rule(dueDate: friday, calendar: calendar)
            #expect(TaskRepeat(rule: rule, dueDate: friday, calendar: calendar) == choice)
        }
        #expect(TaskRepeat(rule: .daily(interval: 3), dueDate: friday, calendar: calendar) == nil)
    }

    @Test func dailyRulesKeepLocalTimeAcrossTheClockChange() throws {
        // Europe/Berlin: its DST rules don't depend on the host's tzdata version (see HouseholdCalendarTests).
        let berlin = HouseholdCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let formatter = ISO8601DateFormatter()
        let start = try #require(formatter.date(from: "2026-10-24T09:00:00+02:00"))
        let end = try #require(formatter.date(from: "2026-10-28T00:00:00+01:00"))
        let every = RecurrenceEngine().occurrences(
            of: .daily(interval: 1), start: start, end: nil, in: DateInterval(start: start, end: end), calendar: berlin)
        let expected = try [
            "2026-10-24T09:00:00+02:00", "2026-10-25T09:00:00+01:00", "2026-10-26T09:00:00+01:00",
            "2026-10-27T09:00:00+01:00",
        ].map { try #require(formatter.date(from: $0)) }
        #expect(every == expected)
        let second = RecurrenceEngine().occurrences(
            of: .daily(interval: 2), start: start, end: nil, in: DateInterval(start: start, end: end), calendar: berlin)
        #expect(second == [expected[0], expected[2]])
    }

    @Test(arguments: [0, 366])
    func dailyIntervalsAreBounded(interval: Int) {
        #expect(throws: RecurrenceRuleError.self) { try RecurrenceRule.daily(interval: interval).validate() }
    }

    // MARK: Board

    private struct Fixture {
        let container: ModelContainer
        let board: TaskBoardService
        let columns: [UUID]

        func context() -> ModelContext { ModelContext(container) }

        func tasks() throws -> [TaskItem] {
            try context().fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        func open() throws -> [TaskItem] {
            try tasks().filter { $0.completedAt == nil }
        }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let board = TaskBoardService.make(container: container)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        // Backups need the household settings row, as the app always has one.
        try await TransactionService.make(container: container).ensureSettings(currencyCode: "CAD", now: now)
        let ordered = FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)])
        let columns = try ModelContext(container).fetch(ordered).map(\.id)
        return Fixture(container: container, board: board, columns: columns)
    }

    private func draft(_ rule: RecurrenceRule?, due: Date?) -> TaskDraft {
        TaskDraft(
            title: "Water plants", notes: "Balcony too", priority: .high, dueDate: due, recurrence: rule,
            timeZone: zone)
    }

    @Test func completingARepeatingTaskAddsTheNextOneOnce() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let due = day(2026, 9, 25)
        let id = try await board.createTask(draft(.weekly(interval: 1, weekday: 6), due: due), now: now)
        let first = try await board.addSubtask(titled: "Front", to: id, now: now)
        try await board.addSubtask(titled: "Back", to: id, now: now)
        try await board.setSubtaskCompleted(true, subtask: first, now: now)

        try await board.setTaskCompleted(true, task: id, now: now)
        let next = try #require(try fixture.open().first)
        #expect(next.id != id)
        #expect(next.title == "Water plants" && next.notes == "Balcony too" && next.priority == .high)
        #expect(next.dueDate == day(2026, 10, 2))
        #expect(next.columnID == fixture.columns.first, "Completed from the first column, so the next goes there")
        #expect(next.recurrence == .weekly(interval: 1, weekday: 6))
        let steps = try fixture.context().fetch(FetchDescriptor<SubtaskItem>()).filter { $0.taskID == next.id }
        #expect(steps.map(\.title).sorted() == ["Back", "Front"])
        #expect(steps.allSatisfy { !$0.isCompleted }, "Subtasks start unticked")

        let done = try #require(try fixture.tasks().first { $0.id == id })
        #expect(done.recurrenceRuleData == nil && done.recurrenceTimeZoneIdentifier == nil)
        #expect(done.completedAt != nil, "The completed task stays as history")

        // Reopening and completing again adds nothing: the rule moved on.
        try await board.setTaskCompleted(false, task: id, now: now)
        try await board.setTaskCompleted(true, task: id, now: now)
        #expect(try fixture.tasks().count == 2)
    }

    @Test func theNextTaskGoesBackToTheColumnItCameFrom() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let id = try await board.createTask(draft(.daily(interval: 1), due: day(2026, 9, 25)), now: now)
        try await board.moveTask(id, to: fixture.columns[1], at: 0, now: now)
        try await board.moveTask(id, to: fixture.columns[2], at: 0, now: now)
        let next = try #require(try fixture.open().first)
        #expect(next.columnID == fixture.columns[1])
        #expect(next.dueDate == day(2026, 9, 26))
    }

    @Test func theNextDateCountsFromTheDueDateNotTheCompletionDate() async throws {
        let fixture = try await makeFixture()
        let id = try await fixture.board.createTask(draft(.monthlyOnDay(day: 31), due: day(2026, 1, 31)), now: now)
        // Completed months late: still the next date after Jan 31.
        try await fixture.board.setTaskCompleted(true, task: id, now: now)
        let february = try #require(try fixture.open().first)
        #expect(february.dueDate == day(2026, 2, 28))
        try await fixture.board.setTaskCompleted(true, task: february.id, now: now)
        let march = try #require(try fixture.open().first)
        #expect(march.dueDate == day(2026, 3, 31), "The rule keeps day 31 after a short month")
    }

    @Test func stoppingTheRepeatEndsTheSeries() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let id = try await board.createTask(draft(.daily(interval: 1), due: day(2026, 9, 25)), now: now)
        try await board.updateTask(id, with: draft(nil, due: day(2026, 9, 25)), now: now)
        try await board.setTaskCompleted(true, task: id, now: now)
        #expect(try fixture.tasks().count == 1)
    }

    @Test func aRepeatNeedsADueDateAndAValidRule() async throws {
        let fixture = try await makeFixture()
        await #expect(throws: TaskBoardError.repeatNeedsDueDate) {
            try await fixture.board.createTask(draft(.daily(interval: 1), due: nil), now: now)
        }
        await #expect(throws: TaskBoardError.invalidRepeat) {
            try await fixture.board.createTask(draft(.daily(interval: 0), due: day(2026, 9, 25)), now: now)
        }
        #expect(try fixture.tasks().isEmpty)
    }

    // MARK: Review follow-ups (Sprint 13 data-safety review)

    @Test func columnChangesCompleteRepeatingTasksWithoutAddingCopies() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let due = day(2026, 9, 25)
        // Owner decision 21: making In Progress the done column completes both tasks but adds no next ones.
        for title in ["A", "B"] {
            var entry = draft(.daily(interval: 1), due: due)
            entry.title = title
            try await board.createTask(entry, in: fixture.columns[1], now: now)
        }
        try await board.moveColumn(fixture.columns[1], to: 2, now: now)
        #expect(try fixture.tasks().count == 2)
        #expect(try fixture.tasks().allSatisfy { $0.completedAt != nil && $0.recurrenceRuleData != nil })
        // Moving it back reopens both, still repeating: one series each.
        try await board.moveColumn(fixture.columns[1], to: 1, now: now)
        #expect(try fixture.open().count == 2)
        #expect(try fixture.tasks().allSatisfy { $0.recurrenceRuleData != nil })
        // Editing a task the column change completed keeps its rule.
        try await board.moveColumn(fixture.columns[1], to: 2, now: now)
        let first = try #require(try fixture.tasks().first)
        var edit = draft(.daily(interval: 1), due: due)
        edit.title = "A renamed"
        try await board.updateTask(first.id, with: edit, now: now)
    }

    @Test func creatingIntoDoneAddsTheNextOneButDeletingAColumnIntoDoneDoesNot() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let done = try #require(fixture.columns.last)
        try await board.createTask(draft(.daily(interval: 1), due: day(2026, 9, 25)), in: done, now: now)
        #expect(try fixture.open().map(\.dueDate) == [day(2026, 9, 26)])
        #expect(try fixture.open().first?.columnID == fixture.columns.first)

        let extra = try await board.createColumn(named: "Waiting", now: now)
        let weekly = draft(.weekly(interval: 1, weekday: 6), due: day(2026, 9, 25))
        let waiting = try await board.createTask(weekly, in: extra, now: now)
        try await board.deleteColumn(extra, movingTasksTo: done, now: now)
        let moved = try #require(try fixture.tasks().first { $0.id == waiting })
        #expect(moved.completedAt != nil && moved.recurrenceRuleData != nil, "A column change keeps the rule")
        #expect(try !fixture.open().contains { $0.dueDate == day(2026, 10, 2) })
    }

    @Test func aCompletedTaskCantStartASecondSeries() async throws {
        let fixture = try await makeFixture()
        let board = fixture.board
        let id = try await board.createTask(draft(.daily(interval: 1), due: day(2026, 9, 25)), now: now)
        try await board.setTaskCompleted(true, task: id, now: now)
        await #expect(throws: TaskBoardError.repeatOnCompletedTask) {
            try await board.updateTask(id, with: draft(.daily(interval: 1), due: day(2026, 9, 25)), now: now)
        }
        // Editing its other fields still works.
        try await board.updateTask(id, with: draft(nil, due: day(2026, 9, 25)), now: now)
    }

    @Test func dailySeriesPostOncePerDayAndSkipLongHistories() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let start = day(2026, 9, 1).addingTimeInterval(9 * 3600)
        let series = try await ledger.createSeries(
            templateAmount: Money(minorUnits: 500, currencyCode: "CAD"), type: .expense, rule: .daily(interval: 2),
            timeZone: zone, startDate: start, now: now)
        let third = try #require(calendar.calendar.date(byAdding: .day, value: 2, to: start))
        try await ledger.materialize(seriesID: series, occurrence: third, now: now)
        await #expect(throws: LedgerError.alreadyMaterialized) {
            try await ledger.materialize(seriesID: series, occurrence: third, now: now)
        }
        let offDay = try #require(calendar.calendar.date(byAdding: .day, value: 1, to: start))
        await #expect(throws: LedgerError.notAnOccurrence) {
            try await ledger.materialize(seriesID: series, occurrence: offDay, now: now)
        }

        // A window years after the start: the engine starts near the window, and times stay local (Berlin: stable DST).
        let berlin = HouseholdCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let formatter = ISO8601DateFormatter()
        let old = try #require(formatter.date(from: "2020-01-01T09:00:00+01:00"))
        let windowStart = try #require(formatter.date(from: "2026-09-01T00:00:00+02:00"))
        let windowEnd = try #require(formatter.date(from: "2026-09-04T00:00:00+02:00"))
        let result = RecurrenceEngine().occurrences(
            of: .daily(interval: 1), start: old, end: nil, in: DateInterval(start: windowStart, end: windowEnd),
            calendar: berlin)
        let expected = try [
            "2026-09-01T09:00:00+02:00", "2026-09-02T09:00:00+02:00", "2026-09-03T09:00:00+02:00",
        ].map { try #require(formatter.date(from: $0)) }
        #expect(result == expected)
    }

    @Test func dailySeriesTravelInBackups() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await ledger.createSeries(
            templateAmount: Money(minorUnits: 500, currencyCode: "CAD"), type: .expense, rule: .daily(interval: 3),
            timeZone: zone, startDate: day(2026, 9, 1), now: now)
        let service = BackupService.make(container: container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.recurringTransactions.first?.rule == .daily(interval: 3))
        try BackupValidator.validate(backup)
        let data = try BackupDTO.encoder().encode(backup)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: data)
        #expect(decoded.recurringTransactions.first?.rule == .daily(interval: 3))
    }

    // MARK: Backup

    @Test func repeatsTravelInBackupsAndAreValidated() async throws {
        let fixture = try await makeFixture()
        try await fixture.board.createTask(draft(.monthlyOnDay(day: 15), due: day(2026, 10, 15)), now: now)
        let service = BackupService.make(container: fixture.container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        let exported = try #require(backup.taskItems.first)
        #expect(exported.recurrenceRule == .monthlyOnDay(day: 15))
        #expect(exported.recurrenceTimeZoneIdentifier == zone.identifier)
        try BackupValidator.validate(backup)

        let target = try await makeFixture()
        _ = try await BackupService.make(container: target.container).restore(backup, availableMedia: [], now: now)
        let restored = try #require(try target.tasks().first)
        #expect(restored.recurrence == .monthlyOnDay(day: 15))
        #expect(restored.recurrenceTimeZoneIdentifier == zone.identifier)

        func variant(_ change: (inout BackupDTO.TaskDTO) -> Void) -> BackupDTO {
            var copy = backup
            change(&copy.taskItems[0])
            return copy
        }
        let cases: [(BackupDTO, BackupError)] = [
            (
                variant { $0.recurrenceTimeZoneIdentifier = nil },
                .inconsistentLink(entity: "taskItems", field: "recurrenceTimeZoneIdentifier")
            ),
            (variant { $0.dueDate = nil }, .inconsistentLink(entity: "taskItems", field: "recurrenceRule")),
            (
                variant { $0.recurrenceRule = .daily(interval: 0) },
                .invalidValue(
                    entity: "taskItems", field: "recurrenceRule", value: "\(RecurrenceRule.daily(interval: 0))")
            ),
            (
                variant { $0.recurrenceTimeZoneIdentifier = "Mars/Olympus" },
                .invalidValue(entity: "taskItems", field: "recurrenceTimeZoneIdentifier", value: "Mars/Olympus")
            ),
        ]
        for (file, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(file) }
        }
    }

    @Test func tasksFromOlderBackupsHaveNoRepeat() throws {
        let json = #"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Old",
            "columnID":"7F9619FF-8B86-D011-B42D-00C04FC964FF",
            "priority":"medium","sortOrder":1,"createdAt":0,"updatedAt":0}
            """#
        let task = try JSONDecoder().decode(BackupDTO.TaskDTO.self, from: Data(json.utf8))
        #expect(task.recurrenceRule == nil && task.recurrenceTimeZoneIdentifier == nil)
    }
}
