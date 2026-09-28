import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 26: a task's optional due time (SchemaV5 `dueTimeMinutes`, minutes after local midnight). A task with a
/// time reminds at it on its due day; one without, and every bill (the day before), at the "Reminder default time".
/// Recurring occurrences keep the time, and backups (format v6) carry it.
struct TaskDueTimeTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let noon = calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        return calendar.startOfDay(for: noon ?? .distantPast)
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.calendar.date(from: parts) ?? .distantPast
    }

    // MARK: Time of day

    @Test(arguments: [(0, true), (540, true), (1_439, true), (-1, false), (1_440, false), (10_000, false)])
    func aTimeIsMinutesAfterMidnight(minutes: Int, valid: Bool) {
        #expect(TimeOfDay.isValid(minutes) == valid)
    }

    @Test(arguments: [0, 1, 540, 1_110, 1_439])
    func minutesRoundTripThroughADate(minutes: Int) {
        let date = TimeOfDay.date(minutes: minutes, onDayOf: day(2026, 9, 28), calendar: calendar)
        #expect(calendar.startOfDay(for: date) == day(2026, 9, 28))
        #expect(TimeOfDay.minutes(of: date, calendar: calendar) == minutes)
    }

    // MARK: Board

    private struct Fixture {
        let container: ModelContainer
        let board: TaskBoardService

        func tasks() throws -> [TaskItem] {
            try ModelContext(container).fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        func task(_ id: UUID) throws -> TaskItem {
            try #require(try tasks().first { $0.id == id })
        }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let board = TaskBoardService.make(container: container)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        // Backups need the household settings row, as the app always has one.
        try await TransactionService.make(container: container).ensureSettings(currencyCode: "CAD", now: now)
        return Fixture(container: container, board: board)
    }

    private func draft(due: Date?, time: Int?, repeating rule: RecurrenceRule? = nil) -> TaskDraft {
        TaskDraft(title: "Water plants", dueDate: due, dueTimeMinutes: time, recurrence: rule, timeZone: zone)
    }

    @Test(arguments: [nil, 0, 540, 1_110, 1_439] as [Int?])
    func createAndUpdateKeepTheTime(time: Int?) async throws {
        let fixture = try await makeFixture()
        let id = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: time), now: now)
        #expect(try fixture.task(id).dueTimeMinutes == time)
        try await fixture.board.updateTask(id, with: draft(due: day(2026, 9, 29), time: 480), now: now)
        #expect(try fixture.task(id).dueTimeMinutes == 480)
        try await fixture.board.updateTask(id, with: draft(due: day(2026, 9, 29), time: time), now: now)
        #expect(try fixture.task(id).dueTimeMinutes == time)
        #expect(try fixture.task(id).dueDate == day(2026, 9, 29), "The time never moves the due day")
    }

    @Test func clearingTheDateClearsTheTime() async throws {
        let fixture = try await makeFixture()
        let id = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 1_110), now: now)
        try await fixture.board.updateTask(id, with: draft(due: nil, time: nil), now: now)
        let task = try fixture.task(id)
        #expect(task.dueDate == nil && task.dueTimeMinutes == nil)
    }

    enum BadTime: CaseIterable, Sendable {
        case withoutADate
        case negative
        case pastMidnight
    }

    private func badDraft(_ bad: BadTime) -> (TaskDraft, TaskBoardError) {
        switch bad {
        case .withoutADate: return (draft(due: nil, time: 540), .timeNeedsDueDate)
        case .negative: return (draft(due: day(2026, 9, 28), time: -1), .invalidDueTime)
        case .pastMidnight: return (draft(due: day(2026, 9, 28), time: 1_440), .invalidDueTime)
        }
    }

    /// Refused, not dropped: a caller never silently loses a time it meant to keep.
    @Test(arguments: BadTime.allCases)
    func aTimeWithoutADateOrOutOfRangeIsRefused(bad: BadTime) async throws {
        let fixture = try await makeFixture()
        let (entry, error) = badDraft(bad)
        await #expect(throws: error) {
            try await fixture.board.createTask(entry, now: now)
        }
        #expect(try fixture.tasks().isEmpty)
        let id = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 600), now: now)
        await #expect(throws: error) {
            try await fixture.board.updateTask(id, with: entry, now: now)
        }
        #expect(try fixture.task(id).dueTimeMinutes == 600, "A refused edit changes nothing")
        await #expect(throws: error) {
            try await fixture.board.createTasks([draft(due: day(2026, 9, 28), time: nil), entry], now: now)
        }
        #expect(try fixture.tasks().count == 1, "A batch with a bad time adds nothing")
    }

    @Test(arguments: [nil, 0, 1_110] as [Int?])
    func theNextOccurrenceKeepsTheTime(time: Int?) async throws {
        let fixture = try await makeFixture()
        let id = try await fixture.board.createTask(
            draft(due: day(2026, 9, 25), time: time, repeating: .weekly(interval: 1, weekday: 6)), now: now)
        try await fixture.board.setTaskCompleted(true, task: id, now: now)
        let next = try #require(try fixture.tasks().first { $0.completedAt == nil })
        #expect(next.id != id)
        #expect(next.dueDate == day(2026, 10, 2))
        #expect(next.dueTimeMinutes == time)
        #expect(try fixture.task(id).dueTimeMinutes == time, "The completed one keeps its own time")
    }

    @Test func reminderSourcesCarryTheTime() async throws {
        let fixture = try await makeFixture()
        let timed = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 1_110), now: now)
        let untimed = try await fixture.board.createTask(draft(due: day(2026, 9, 29), time: nil), now: now)
        try await fixture.board.createTask(draft(due: nil, time: nil), now: now)
        let sources = try await fixture.board.reminderSources()
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.taskID, $0) })
        #expect(sources.count == 2, "A task without a date has no reminder")
        #expect(byID[timed]?.dueTimeMinutes == 1_110)
        #expect(byID[untimed].map { $0.dueTimeMinutes == nil } == true)
    }

    // MARK: Planner

    private let wording = ReminderWording(
        taskTitle: "Task due today", taskBody: { $0 }, billTitle: "Bill due tomorrow",
        billBody: { name in "\(name ?? "A bill") is due tomorrow." })

    private func bill(_ date: Date, title: String = "Rent") -> UpcomingOccurrence {
        UpcomingOccurrence(
            seriesID: UUID(), date: date, amount: Money(minorUnits: 120_000, currencyCode: "CAD"), type: .expense,
            title: title)
    }

    private func plan(
        tasks: [TaskReminderSource], bills: [UpcomingOccurrence] = [], defaultTime: Int = 540, now: Date,
        calendar: HouseholdCalendar? = nil, limit: Int = ReminderPlanner.defaultLimit
    ) -> [PlannedReminder] {
        ReminderPlanner().plan(
            tasks: tasks, bills: bills,
            settings: ReminderSettings(tasksDue: true, billsDue: true, defaultTimeMinutes: defaultTime),
            wording: wording, now: now, calendar: calendar ?? self.calendar, limit: limit)
    }

    @Test func theDefaultTimeIsNineUntilTheUserSetsOne() {
        #expect(ReminderSettings(tasksDue: true, billsDue: true).defaultTimeMinutes == 540)
        #expect(TimeOfDay.defaultReminderMinutes == 9 * 60)
    }

    private func task(due: Date, time: Int?) -> TaskReminderSource {
        TaskReminderSource(taskID: UUID(), title: "Water", dueDate: due, dueTimeMinutes: time)
    }

    /// (task time, default time, hour, minute): when it fires on its due day.
    static let fireTimes: [(Int?, Int, Int, Int)] = [
        (nil, 540, 9, 0),  // no time: the default, 9:00
        (nil, 1_290, 21, 30),  // no time: the user's default
        (1_110, 540, 18, 30),  // its own time wins
        (1_110, 1_290, 18, 30),
        (0, 540, 0, 0),  // midnight of the due day
        (1_439, 540, 23, 59),
        (nil, 5_000, 9, 0),  // an unreadable default reads as 9:00
    ]

    @Test(arguments: TaskDueTimeTests.fireTimes)
    func aTaskRemindsOnItsDueDayAtItsTimeOrTheDefault(time: Int?, defaultTime: Int, hour: Int, minute: Int) {
        let source = task(due: day(2026, 9, 28), time: time)
        let reminders = plan(tasks: [source], defaultTime: defaultTime, now: at(2026, 9, 26, 8))
        #expect(reminders.map(\.fireDate) == [at(2026, 9, 28, hour, minute)])
        #expect(reminders.first?.kind == .taskDue)
    }

    @Test(arguments: [0, 540, 1_290, 1_439])
    func billsRemindAtTheDefaultTimeTheDayBefore(defaultTime: Int) {
        let rent = bill(at(2026, 10, 1, 9))
        let reminders = plan(tasks: [], bills: [rent], defaultTime: defaultTime, now: at(2026, 9, 26))
        #expect(reminders.map(\.fireDate) == [at(2026, 9, 30, defaultTime / 60, defaultTime % 60)])
        #expect(reminders.first?.kind == .billDue)
    }

    /// (task time, fires): now is 12:00 on the due day, so a time already past today is skipped.
    static let pastCases: [(Int?, Bool)] = [
        (540, false), (719, false), (720, false), (721, true), (1_110, true),
        (nil, false),  // the 9:00 default has passed
    ]

    @Test(arguments: TaskDueTimeTests.pastCases)
    func pastTimesAreSkipped(time: Int?, fires: Bool) {
        let source = task(due: day(2026, 9, 28), time: time)
        #expect(plan(tasks: [source], now: at(2026, 9, 28, 12)).count == (fires ? 1 : 0))
    }

    // Europe/Berlin: its DST rules don't depend on the host's tzdata version (see HouseholdCalendarTests). 2026-03-29
    // skips 02:00–02:59; 2026-10-25 repeats them.
    private var berlin: HouseholdCalendar { HouseholdCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!) }

    private func iso(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// (task time, default time): 02:30 either way, on the day that skips it.
    static let springCases: [(Int?, Int)] = [(150, 540), (nil, 150)]

    @Test(arguments: TaskDueTimeTests.springCases)
    func aTimeTheSpringForwardDaySkipsFiresAtTheNextValidTime(time: Int?, defaultTime: Int) throws {
        let noon = try iso("2026-03-29T12:00:00+02:00")
        let start = try iso("2026-03-28T12:00:00+01:00")
        let earliest = try iso("2026-03-29T03:00:00+02:00")
        let latest = try iso("2026-03-29T03:30:00+02:00")
        let source = task(due: berlin.startOfDay(for: noon), time: time)
        let reminders = plan(tasks: [source], defaultTime: defaultTime, now: start, calendar: berlin)
        let fire = try #require(reminders.first?.fireDate, "Not dropped")
        #expect(fire >= earliest && fire <= latest)
    }

    @Test func aBillReminderOnTheSpringForwardDayIsKept() throws {
        let due = try iso("2026-03-30T09:00:00+02:00")
        let start = try iso("2026-03-28T12:00:00+01:00")
        let dayBefore = try iso("2026-03-29T12:00:00+02:00")
        let reminders = plan(tasks: [], bills: [bill(due)], defaultTime: 150, now: start, calendar: berlin)
        let fire = try #require(reminders.first?.fireDate, "Not dropped")
        #expect(berlin.startOfDay(for: fire) == berlin.startOfDay(for: dayBefore))
        #expect(berlin.calendar.component(.hour, from: fire) == 3)
    }

    @Test func aTimeTheFallBackDayRepeatsFiresOnceTheFirstTime() throws {
        let noon = try iso("2026-10-25T12:00:00+01:00")
        let start = try iso("2026-10-24T12:00:00+02:00")
        let first = try iso("2026-10-25T02:30:00+02:00")
        let source = task(due: berlin.startOfDay(for: noon), time: 150)
        let reminders = plan(tasks: [source], now: start, calendar: berlin)
        #expect(reminders.map(\.fireDate) == [first])
    }

    @Test func anOrdinaryDayKeepsTheWallClockTimeInTheCalendarsZone() throws {
        let noon = try iso("2026-09-28T12:00:00+02:00")
        let start = try iso("2026-09-27T12:00:00+02:00")
        let evening = try iso("2026-09-28T18:30:00+02:00")
        let source = task(due: berlin.startOfDay(for: noon), time: 1_110)
        let reminders = plan(tasks: [source], now: start, calendar: berlin)
        #expect(reminders.map(\.fireDate) == [evening])
    }

    /// The cap keeps the soonest reminders, ordered by fire time (then id), whatever mix of times and bills.
    @Test(arguments: [0, 1, 25, ReminderPlanner.defaultLimit])
    func theCapKeepsTheSoonestInOrder(limit: Int) {
        let tasks = (0..<70).map { index in
            TaskReminderSource(
                taskID: UUID(), title: "T\(index)", dueDate: day(2026, 9, 27 + index % 10),
                dueTimeMinutes: index % 3 == 0 ? nil : (index * 37) % TimeOfDay.minutesPerDay)
        }
        let bills = (0..<10).map { index in bill(at(2026, 9, 28 + index, 9), title: "B\(index)") }
        let start = at(2026, 9, 26, 12)
        let all = plan(tasks: tasks, bills: bills, defaultTime: 600, now: start, limit: Int.max)
        let capped = plan(tasks: tasks, bills: bills, defaultTime: 600, now: start, limit: limit)
        #expect(all.count == 80)
        #expect(capped.count == limit)
        #expect(capped == Array(all.prefix(limit)))
        let inOrder = zip(all, all.dropFirst()).allSatisfy { pair in
            (pair.0.fireDate, pair.0.id) < (pair.1.fireDate, pair.1.id)
        }
        #expect(inOrder, "Soonest first, then by id")
        let lastKept = capped.last?.fireDate ?? .distantPast
        #expect(all.dropFirst(limit).allSatisfy { $0.fireDate >= lastKept }, "Nothing sooner is left out")
    }

    // MARK: Backup

    @Test func aVersion6BackupCarriesTheTimeAndRestoresIt() async throws {
        let fixture = try await makeFixture()
        let timed = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 1_110), now: now)
        let untimed = try await fixture.board.createTask(draft(due: day(2026, 9, 29), time: nil), now: now)
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        #expect(backup.schemaVersion == 6)
        #expect(backup.taskItems.first { $0.id == timed }?.dueTimeMinutes == 1_110)
        #expect(backup.taskItems.first { $0.id == untimed }.map { $0.dueTimeMinutes == nil } == true)
        let data = try BackupDTO.encoder().encode(backup)
        #expect(String(data: data, encoding: .utf8)?.contains("\"dueTimeMinutes\"") == true)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: data)
        #expect(decoded == backup)
        try BackupValidator.validate(decoded)

        let target = try await makeFixture()
        _ = try await BackupService.make(container: target.container).restore(decoded, availableMedia: [], now: now)
        #expect(try target.task(timed).dueTimeMinutes == 1_110)
        #expect(try target.task(untimed).dueTimeMinutes == nil)
        let again = try await BackupService.make(container: target.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        #expect(again.taskItems == backup.taskItems)
    }

    /// A v5 file (written before Sprint 26: no `dueTimeMinutes` key anywhere) restores every task with no time.
    @Test func aVersion5FileWithoutTimesRestoresWithNone() async throws {
        let fixture = try await makeFixture()
        let id = try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: nil), now: now)
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        let data = try BackupDTO.encoder().encode(backup)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 5
        let tasks = try #require(object["taskItems"] as? [[String: Any]])
        object["taskItems"] = tasks.map { task in task.filter { $0.key != "dueTimeMinutes" } }
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(String(data: older, encoding: .utf8)?.contains("dueTimeMinutes") == false)
        let file = try BackupDTO.decoder().decode(BackupDTO.self, from: older)
        #expect(file.schemaVersion == 5)
        #expect(file.taskItems.allSatisfy { $0.dueTimeMinutes == nil })

        let target = try await makeFixture()
        _ = try await BackupService.make(container: target.container).restore(file, availableMedia: [], now: now)
        let restored = try target.task(id)
        #expect(restored.dueDate == day(2026, 9, 28) && restored.dueTimeMinutes == nil)
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func anOlderFileWithATimeIsRefused(version: Int) async throws {
        let fixture = try await makeFixture()
        try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 1_110), now: now)
        var older = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        older.schemaVersion = version
        if version == 1 {
            older.settings.startingBalanceMinorUnits = 0
            older.settings.startingBalanceDate = now
        }
        #expect(throws: BackupError.invalidValue(entity: "taskItems", field: "dueTimeMinutes", value: "1110")) {
            try BackupValidator.validate(older)
        }
    }

    @Test func theValidatorRefusesATimeTheAppCouldNotHaveWritten() async throws {
        let fixture = try await makeFixture()
        try await fixture.board.createTask(draft(due: day(2026, 9, 28), time: 1_110), now: now)
        let backup = try await BackupService.make(container: fixture.container).snapshot(now: now, appVersion: "1") {
            _ in nil
        }
        var outOfRange = backup
        outOfRange.taskItems[0].dueTimeMinutes = 1_440
        #expect(throws: BackupError.invalidValue(entity: "taskItems", field: "dueTimeMinutes", value: "1440")) {
            try BackupValidator.validate(outOfRange)
        }
        var withoutADate = backup
        withoutADate.taskItems[0].dueDate = nil
        #expect(throws: BackupError.inconsistentLink(entity: "taskItems", field: "dueTimeMinutes")) {
            try BackupValidator.validate(withoutADate)
        }
    }
}
