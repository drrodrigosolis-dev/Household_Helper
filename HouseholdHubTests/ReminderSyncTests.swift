import Foundation
import HouseholdHubCore
import Testing
import UserNotifications

@testable import HouseholdHub

/// Stands in for the system notification center: keeps pending requests by identifier, as the center does, and can
/// hold one `add` open to let a second refresh start in the middle of the first.
@MainActor
final class FakeReminderCenter: ReminderCenter {
    private(set) var requests: [String: UNNotificationRequest] = [:]
    /// The next `add` waits until `release()`.
    var holdsNextAdd = false
    private(set) var isHolding = false
    private var gate: CheckedContinuation<Void, Never>?

    func pendingIdentifiers() async -> [String] {
        Array(requests.keys)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            requests[identifier] = nil
        }
    }

    func isAuthorized() async -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async {
        if holdsNextAdd {
            holdsNextAdd = false
            await withCheckedContinuation { continuation in
                gate = continuation
                isHolding = true
            }
        }
        requests[request.identifier] = request
    }

    func release() {
        isHolding = false
        gate?.resume()
        gate = nil
    }

    /// Each pending request's wall-clock fire time, "day hour:minute".
    var fireTimes: [String: String] {
        requests.mapValues { request in
            let parts = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            return String(format: "%ld %ld:%02ld", parts?.day ?? -1, parts?.hour ?? -1, parts?.minute ?? -1)
        }
    }
}

/// Sprint 26 data-safety review B2 and S3: changing the "Reminder default time" reschedules every pending reminder at
/// the new time and leaves none at the old one, even when it changes twice in quick succession. Serialized:
/// refreshes share one queue, so a test's refresh must not be superseded by another test's.
@MainActor
@Suite(.serialized)
struct ReminderSyncTests {
    private struct Household {
        let services: AppServices
        let untimed: String
        let timed: String
    }

    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    /// 2026-09-28 08:00 in Vancouver; both tasks are due the next day.
    private static var now: Date {
        calendar.calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8)) ?? .distantPast
    }

    /// One task due 2026-09-29 without a time (it reminds at the default time), one at 18:30.
    private static func makeHousehold() async throws -> Household {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let services = AppServices(container: container)
        try await services.board.seedDefaultColumnsIfNeeded(now: now)
        try await services.transactions.ensureSettings(currencyCode: "CAD", now: now)
        let due = calendar.startOfDay(for: now.addingTimeInterval(86_400))
        let zone = calendar.timeZone
        let untimed = try await services.board.createTask(
            TaskDraft(title: "Water plants", dueDate: due, timeZone: zone), now: now)
        let timed = try await services.board.createTask(
            TaskDraft(title: "Call", dueDate: due, dueTimeMinutes: 1_110, timeZone: zone), now: now)
        return Household(services: services, untimed: "task-\(untimed.uuidString)", timed: "task-\(timed.uuidString)")
    }

    private static func refresh(_ household: Household, defaultTime: Int, center: FakeReminderCenter) async {
        let settings = ReminderSettings(tasksDue: true, billsDue: false, defaultTimeMinutes: defaultTime)
        await ReminderSync.refresh(
            household.services, settings: settings, budgetAlerts: false, center: center, now: now, calendar: calendar)
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        var tries = 0
        while !condition(), tries < 10_000 {
            tries += 1
            await Task.yield()
        }
    }

    /// The untimed task follows each new default time; the timed one keeps its own.
    @Test func changingTheDefaultTimeReschedulesAtTheNewTime() async throws {
        let household = try await Self.makeHousehold()
        let center = FakeReminderCenter()
        await Self.refresh(household, defaultTime: 540, center: center)
        #expect(center.fireTimes == [household.untimed: "29 9:00", household.timed: "29 18:30"])

        await Self.refresh(household, defaultTime: 1_290, center: center)
        #expect(center.fireTimes == [household.untimed: "29 21:30", household.timed: "29 18:30"], "None at 9:00")

        await Self.refresh(household, defaultTime: 0, center: center)
        #expect(center.fireTimes == [household.untimed: "29 0:00", household.timed: "29 18:30"])
    }

    /// The first refresh is held in the middle of adding its 9:00 reminder while the second (21:30) starts; when it
    /// resumes, the second still has the last word.
    @Test func aQuickSecondChangeLeavesOnlyItsOwnReminders() async throws {
        let household = try await Self.makeHousehold()
        let center = FakeReminderCenter()
        center.holdsNextAdd = true
        let first = Task { @MainActor in
            await Self.refresh(household, defaultTime: 540, center: center)
        }
        await Self.waitUntil { center.isHolding }
        #expect(center.isHolding, "The first refresh is mid-way")
        let before = ReminderSync.generation
        let second = Task { @MainActor in
            await Self.refresh(household, defaultTime: 1_290, center: center)
        }
        await Self.waitUntil { ReminderSync.generation > before }
        #expect(ReminderSync.generation > before, "The second refresh has started")
        center.release()
        await first.value
        await second.value
        #expect(center.fireTimes == [household.untimed: "29 21:30", household.timed: "29 18:30"])
    }
}
