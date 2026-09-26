import Foundation
import Testing

@testable import HouseholdHubCore

/// Sprint 14 (owner decision 23): deterministic search and the local reminder plan.
struct SearchAndReminderTests {
    private let english = Locale(identifier: "en_CA")

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    // MARK: Search

    @Test(arguments: [
        ("cafe", true),  // accents and case ignored
        ("LUNA café", true),  // every word, any order, any field
        ("luna pizza", false),  // every word must match
        ("47.50", true),  // exact amount
        ("47,50", true),
        ("47.5", true),
        ("47", false),  // not the same amount, and not in the text
        ("", true),  // an empty search keeps everything
        ("   ", true),
    ])
    func searchMatchesWordsAndExactAmounts(query: String, expected: Bool) {
        let search = SearchQuery(query, locale: english)
        #expect(search.matches(["Café Luna", nil, "Dining"], amount: cad(4_750)) == expected)
    }

    @Test func amountWordsStillMatchTextAndNeverMatchWithoutAnAmount() {
        #expect(SearchQuery("2026", locale: english).matches(["Taxes 2026"]))
        #expect(!SearchQuery("12", locale: english).matches(["Rent"]))
        #expect(SearchQuery("12", locale: english).matches(["Rent"], amount: cad(1_200)))
        #expect(!SearchQuery("1.2.3", locale: english).matches(["Rent"], amount: cad(123)))
    }

    // MARK: Reminders

    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private let wording = ReminderWording(
        taskTitle: "Task due today", taskBody: { $0 }, billTitle: "Bill due tomorrow",
        billBody: { name in "\(name ?? "A bill") is due tomorrow." })

    private func bill(_ title: String?, _ date: Date, _ type: TransactionType = .expense) -> UpcomingOccurrence {
        UpcomingOccurrence(seriesID: UUID(), date: date, amount: cad(120_000), type: type, title: title)
    }

    @Test func tasksRemindAtNineOnTheDueDayAndBillsTheDayBefore() {
        let now = at(2026, 9, 26, 8)
        let task = TaskReminderSource(taskID: UUID(), title: "Water plants", dueDate: at(2026, 9, 28))
        let rent = bill("Rent", at(2026, 10, 1, 9))
        let plan = ReminderPlanner().plan(
            tasks: [task], bills: [rent, bill("Salary", at(2026, 10, 1, 9), .income)],
            settings: ReminderSettings(tasksDue: true, billsDue: true), wording: wording, now: now, calendar: calendar)
        #expect(plan.map(\.fireDate) == [at(2026, 9, 28, 9), at(2026, 9, 30, 9)])
        #expect(plan.map(\.kind) == [.taskDue, .billDue], "Income is not a bill")
        #expect(plan.last?.body == "Rent is due tomorrow.")
        #expect(plan.allSatisfy { !$0.body.contains("1,200") && !$0.body.contains("1200") }, "No amounts")
        #expect(plan.first?.id == "task-\(task.taskID.uuidString)")
    }

    @Test func switchesPastTimesAndTheLimitApply() {
        let now = at(2026, 9, 26, 10)
        let today = TaskReminderSource(taskID: UUID(), title: "Late", dueDate: at(2026, 9, 26))
        let later = (1...80).map { index in
            TaskReminderSource(taskID: UUID(), title: "T\(index)", dueDate: at(2026, 9, 26 + index % 20))
        }
        let bills = [bill("Rent", at(2026, 9, 27, 9))]
        let off = ReminderPlanner().plan(
            tasks: later, bills: bills, settings: ReminderSettings(tasksDue: false, billsDue: false),
            wording: wording, now: now, calendar: calendar)
        #expect(off.isEmpty)
        let plan = ReminderPlanner().plan(
            tasks: [today] + later, bills: bills, settings: ReminderSettings(tasksDue: true, billsDue: true),
            wording: wording, now: now, calendar: calendar)
        #expect(plan.count == ReminderPlanner.defaultLimit)
        #expect(!plan.contains { $0.body == "Late" }, "9:00 today has passed")
        #expect(!plan.contains { $0.kind == .billDue }, "The bill's reminder (9:00 today) has passed")
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted(), "Soonest first")
    }
}
