import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 26 data-safety review: a task's due time across clock changes. A repeating task's next occurrence keeps its
/// wall-clock time when the offset changes between them (B1); the editor never moves a stored time just by being
/// opened on a clock-change day (S1); and a time a spring-forward day skips still reminds on that day, even where the
/// skipped hour is the day's first (America/Santiago, S2).
struct TaskDueTimeClockChangeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let wording = ReminderWording(
        taskTitle: "Task due today", taskBody: { $0 }, billTitle: "Bill due tomorrow",
        billBody: { name in "\(name ?? "A bill") is due tomorrow." })

    private static func calendar(_ identifier: String) throws -> HouseholdCalendar {
        HouseholdCalendar(timeZone: try #require(TimeZone(identifier: identifier)))
    }

    // MARK: B1: the next occurrence keeps its time

    /// A repeat whose next due day is on the other side of a clock change.
    struct Crossing: Sendable, CustomTestStringConvertible {
        let zone: String
        let rule: RecurrenceRule
        /// (year, month, day) of the completed task's due day and of the next one's.
        let due: [Int]
        let next: [Int]

        var testDescription: String { "\(zone) \(due) → \(next)" }
    }

    static let crossings: [Crossing] = [
        // America/Vancouver falls back on 2026-11-01 and springs forward on 2027-03-14.
        Crossing(
            zone: "America/Vancouver", rule: .weekly(interval: 1, weekday: 6), due: [2026, 10, 30],
            next: [2026, 11, 6]),
        Crossing(
            zone: "America/Vancouver", rule: .weekly(interval: 1, weekday: 7), due: [2027, 3, 13], next: [2027, 3, 20]),
        Crossing(zone: "America/Vancouver", rule: .monthlyOnDay(day: 15), due: [2026, 10, 15], next: [2026, 11, 15]),
        Crossing(zone: "America/Vancouver", rule: .monthlyOnDay(day: 20), due: [2027, 2, 20], next: [2027, 3, 20]),
        // Europe/Berlin falls back on 2026-10-25.
        Crossing(
            zone: "Europe/Berlin", rule: .weekly(interval: 1, weekday: 6), due: [2026, 10, 23], next: [2026, 10, 30]),
    ]

    private static func day(_ parts: [Int], _ calendar: HouseholdCalendar) throws -> Date {
        let noon = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return calendar.startOfDay(for: try #require(calendar.calendar.date(from: noon)))
    }

    @Test(arguments: TaskDueTimeClockChangeTests.crossings, [0, 90, 540, 1_110, 1_439])
    func theNextOccurrenceKeepsItsTimeAcrossAClockChange(crossing: Crossing, time: Int) async throws {
        let calendar = try Self.calendar(crossing.zone)
        let due = try Self.day(crossing.due, calendar)
        let expectedNext = try Self.day(crossing.next, calendar)
        let zone = calendar.timeZone
        #expect(zone.secondsFromGMT(for: due) != zone.secondsFromGMT(for: expectedNext), "It crosses a clock change")

        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let board = TaskBoardService.make(container: container)
        try await board.seedDefaultColumnsIfNeeded(now: now)
        let draft = TaskDraft(
            title: "Water plants", dueDate: due, dueTimeMinutes: time, recurrence: crossing.rule, timeZone: zone)
        let id = try await board.createTask(draft, now: now)
        try await board.setTaskCompleted(true, task: id, now: now)

        let tasks = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
        let next = try #require(tasks.first { $0.completedAt == nil })
        #expect(next.dueDate == expectedNext)
        #expect(next.dueTimeMinutes == time, "The stored time is the one before it")

        let sources = try await board.reminderSources()
        let source = try #require(sources.first { $0.taskID == next.id })
        let reminders = ReminderPlanner().plan(
            tasks: [source], bills: [], settings: ReminderSettings(tasksDue: true, billsDue: false), wording: wording,
            now: due, calendar: calendar)
        let wallClock = DateComponents(
            year: crossing.next[0], month: crossing.next[1], day: crossing.next[2], hour: time / 60, minute: time % 60)
        let expectedFire = try #require(calendar.calendar.date(from: wallClock))
        #expect(reminders.map(\.fireDate) == [expectedFire], "The same wall-clock time on the new due day")
        #expect(TimeOfDay.minutes(of: expectedFire, calendar: calendar) == time)
    }

    // MARK: S1: the editor keeps a stored time

    static let zones = ["America/Vancouver", "Europe/Berlin", "America/Santiago", "Australia/Sydney", "Asia/Kolkata"]

    /// The picker's `Date` is on a fixed day without a clock change: every time reads back as itself in every zone.
    @Test(arguments: TaskDueTimeClockChangeTests.zones, [0, 30, 150, 540, 1_110, 1_439])
    func aPickerTimeReadsBackUnchanged(zone: String, minutes: Int) throws {
        let calendar = try Self.calendar(zone)
        let date = TimeOfDay.pickerDate(minutes: minutes, calendar: calendar)
        #expect(TimeOfDay.minutes(of: date, calendar: calendar) == minutes)
    }

    /// Europe/Berlin skips 02:00 to 02:59 on 2026-03-29. Built on that day, as the editor did before, 02:30 read as
    /// 03:00 and saving stored 03:00.
    @Test(arguments: [150, 125, 179])
    func openingAndSavingOnASpringForwardDayKeepsTheStoredTime(stored: Int) throws {
        let berlin = try Self.calendar("Europe/Berlin")
        let springDay = try Self.day([2026, 3, 29], berlin)
        let onThatDay = TimeOfDay.date(minutes: stored, onDayOf: springDay, calendar: berlin)
        #expect(TimeOfDay.minutes(of: onThatDay, calendar: berlin) != stored, "The old way moved it")

        let opened = TimeOfDay.pickerDate(minutes: stored, calendar: berlin)
        #expect(TimeOfDay.editedMinutes(picked: opened, opened: opened, stored: stored, calendar: berlin) == stored)
        // Even a picker `Date` that doesn't read back (the old one) keeps the stored minutes while it is untouched.
        #expect(
            TimeOfDay.editedMinutes(picked: onThatDay, opened: onThatDay, stored: stored, calendar: berlin) == stored)
    }

    /// (stored, picked): a picker the user moved saves its own time; a new time has nothing stored to keep.
    static let pickerChanges: [(Int?, Int)] = [(150, 600), (540, 541), (nil, 540), (nil, 150), (1_439, 0)]

    @Test(arguments: TaskDueTimeClockChangeTests.pickerChanges)
    func aMovedPickerSavesItsTime(stored: Int?, picked: Int) throws {
        let berlin = try Self.calendar("Europe/Berlin")
        let opened = TimeOfDay.pickerDate(minutes: stored ?? 540, calendar: berlin)
        let moved = TimeOfDay.pickerDate(minutes: picked, calendar: berlin)
        let saved = TimeOfDay.editedMinutes(picked: moved, opened: opened, stored: stored, calendar: berlin)
        #expect(saved == (moved == opened ? stored ?? picked : picked))
    }

    // MARK: S2: a skipped time stays on its day

    /// America/Santiago's next spring-forward day after June 2026, found from the zone's own rules (so the test
    /// follows tzdata rather than a hardcoded date), and the instant its clocks jump.
    private func santiagoSpringForward() throws -> (calendar: HouseholdCalendar, day: Date, jump: Date) {
        let calendar = try Self.calendar("America/Santiago")
        let zone = calendar.timeZone
        var after = Date(timeIntervalSince1970: 1_780_272_000)  // 2026-06-01
        for _ in 0..<4 {
            let jump = try #require(zone.nextDaylightSavingTimeTransition(after: after))
            if zone.isDaylightSavingTime(for: jump) {
                return (calendar, calendar.startOfDay(for: jump), jump)
            }
            after = jump
        }
        throw SpringForwardNotFound()
    }

    private struct SpringForwardNotFound: Error {}

    @Test(arguments: [0, 1, 30, 59, 60, 90, 540, 1_439])
    func aTimeOnSantiagosSpringForwardDayStaysOnThatDay(minutes: Int) throws {
        let (calendar, day, jump) = try santiagoSpringForward()
        let fire = TimeOfDay.date(minutes: minutes, onDayOf: day, calendar: calendar)
        #expect(calendar.startOfDay(for: fire) == day, "Never the next day's 00:xx")
        let exists = TimeOfDay.minutes(of: fire, calendar: calendar) == minutes
        #expect(exists || fire == jump, "A skipped time is the first valid instant after the jump")
        if day == jump, minutes < 60 {
            // The zone skips the day's midnight hour: 00:xx doesn't exist, so the day's first instant.
            #expect(fire == day)
        }
    }

    @Test(arguments: [0, 30, 540] as [Int], [true, false])
    func aTaskDueOnSantiagosSpringForwardDayRemindsThatDay(minutes: Int, ownTime: Bool) throws {
        let (calendar, day, _) = try santiagoSpringForward()
        let source = TaskReminderSource(
            taskID: UUID(), title: "Water", dueDate: day, dueTimeMinutes: ownTime ? minutes : nil)
        let settings = ReminderSettings(tasksDue: true, billsDue: false, defaultTimeMinutes: ownTime ? 540 : minutes)
        let dayBefore = day.addingTimeInterval(-86_400)
        let reminders = ReminderPlanner().plan(
            tasks: [source], bills: [], settings: settings, wording: wording, now: dayBefore, calendar: calendar)
        let fire = try #require(reminders.first?.fireDate, "Not dropped")
        #expect(calendar.startOfDay(for: fire) == day)
    }
}
