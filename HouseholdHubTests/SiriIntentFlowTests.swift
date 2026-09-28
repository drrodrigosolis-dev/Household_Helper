import Foundation
import SwiftData
import Synchronization
import Testing

@testable import HouseholdHubCore

/// Records the steps a Siri intent flow takes and plays the app's side: the restore flag, the lock and the prompt.
final class FlowProbe: Sendable {
    let steps = Mutex<[String]>([])
    let restoring = Mutex(false)
    let unlocks: Bool
    /// Starts a restore while the prompt is showing.
    let restoreDuringPrompt: Bool
    /// Throws from the prompt, as `requestConfirmation` does when the person declines.
    let declines: Bool

    struct Declined: Error {}

    init(unlocks: Bool = true, restoreDuringPrompt: Bool = false, declines: Bool = false) {
        self.unlocks = unlocks
        self.restoreDuringPrompt = restoreDuringPrompt
        self.declines = declines
    }

    var recorded: [String] {
        steps.withLock { $0 }
    }

    func note(_ step: String) {
        steps.withLock { $0.append(step) }
    }

    /// A flow whose steps only record themselves; `draft` and `write` may add work.
    func flow<Draft>(
        draft: @escaping () async throws -> Draft, write: @escaping (Draft) async throws -> Void = { _ in }
    ) -> SiriIntentFlow<Draft> {
        SiriIntentFlow(
            isRestoring: {
                self.note("restoring?")
                return self.restoring.withLock { $0 }
            },
            unlock: {
                self.note("unlock")
                return self.unlocks
            },
            draft: {
                self.note("draft")
                return try await draft()
            },
            confirm: { _ in
                self.note("confirm")
                if self.restoreDuringPrompt {
                    self.restoring.withLock { $0 = true }
                }
                if self.declines {
                    throw Declined()
                }
            },
            write: { value in
                self.note("write")
                try await write(value)
            }
        )
    }
}

/// Values a fake received, in order.
final class Recorded<Value: Sendable>: Sendable {
    private let values = Mutex<[Value]>([])

    var all: [Value] {
        values.withLock { $0 }
    }

    func append(_ value: Value) {
        values.withLock { $0.append(value) }
    }
}

/// A model that counts how often it is asked.
final class CountingSiriModel: SiriDraftModel {
    let calls = Mutex(0)

    var count: Int {
        calls.withLock { $0 }
    }

    func transaction(_ text: String, categoryNames: [String]) async throws -> SiriTransactionGuess {
        calls.withLock { $0 += 1 }
        return SiriTransactionGuess(amount: "40", kind: "", merchant: "", datePhrase: "", category: "")
    }

    func wishlist(_ text: String) async throws -> SiriWishlistGuess {
        calls.withLock { $0 += 1 }
        return SiriWishlistGuess(name: "headphones", price: "")
    }
}

/// Sprint 25: the order every Siri write follows, with fakes for the lock, the prompt and the restore flag.
struct SiriIntentFlowTests {
    static let now = SiriEntryTests.now
    static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)

    static func refinedDraft(_ model: any SiriDraftModel) async throws -> TransactionDraft {
        try await SiriRefinement.transaction(
            text: "40 coffee", settings: SiriEntryTests.settings(), categories: [], model: model, now: now,
            calendar: calendar
        ).draft
    }

    @Test func theWriteHappensOnceAfterTheConfirmation() async throws {
        let probe = FlowProbe()
        let writes = Recorded<TransactionDraft>()
        let model = CountingSiriModel()
        let draft = try await probe.flow(
            draft: { try await Self.refinedDraft(model) },
            write: { value in writes.append(value) }
        ).run()
        #expect(probe.recorded == ["restoring?", "unlock", "draft", "confirm", "restoring?", "write"])
        #expect(writes.all == [draft])
        #expect(model.count == 1)
    }

    @Test func aLockedAppNeverReachesTheModelOrTheWrite() async throws {
        let probe = FlowProbe(unlocks: false)
        let model = CountingSiriModel()
        await #expect(throws: SiriIntentFlowError.locked) {
            try await probe.flow(draft: { try await Self.refinedDraft(model) }).run()
        }
        #expect(probe.recorded == ["restoring?", "unlock"])
        #expect(model.count == 0)
    }

    @Test func aDeclinedConfirmationNeverWrites() async throws {
        let probe = FlowProbe(declines: true)
        await #expect(throws: FlowProbe.Declined.self) {
            try await probe.flow(draft: { "call the plumber" }).run()
        }
        #expect(probe.recorded == ["restoring?", "unlock", "draft", "confirm"])
    }

    @Test func aRestoreThatStartsDuringTheConfirmationStopsTheWrite() async throws {
        let probe = FlowProbe(restoreDuringPrompt: true)
        await #expect(throws: SiriIntentFlowError.restoring) {
            try await probe.flow(draft: { "call the plumber" }).run()
        }
        #expect(probe.recorded == ["restoring?", "unlock", "draft", "confirm", "restoring?"])
    }

    @Test func nothingStartsWhileARestoreRuns() async throws {
        let probe = FlowProbe()
        probe.restoring.withLock { $0 = true }
        let model = CountingSiriModel()
        await #expect(throws: SiriIntentFlowError.restoring) {
            try await probe.flow(draft: { try await Self.refinedDraft(model) }).run()
        }
        #expect(probe.recorded == ["restoring?"])
        #expect(model.count == 0)
    }

    private static func emptyTask() throws -> TaskDraft {
        try TaskEntry.draft(text: " . ", now: now, calendar: calendar)
    }

    @Test func aDraftErrorStopsTheFlowBeforeThePrompt() async throws {
        let probe = FlowProbe()
        await #expect(throws: SiriEntryError.emptyText) {
            try await probe.flow(draft: { () throws -> TaskDraft in try Self.emptyTask() }).run()
        }
        #expect(probe.recorded == ["restoring?", "unlock", "draft"])
    }

    // MARK: The services refuse the Siri writes during a restore

    @Test func aWriteRefusedByARunningRestoreIsReportedAsRestoring() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: Self.now, now: Self.now)
        let gate = RestoreGate.shared(for: container)
        // The restore starts after the flow's last check, as the services see it.
        gate.beginRestore()
        defer { gate.endRestore() }
        let probe = FlowProbe()
        await #expect(throws: SiriIntentFlowError.restoring) {
            try await probe.flow(
                draft: { try WishlistEntry.draft(text: "headphones for 149", settings: SiriEntryTests.settings()) },
                write: { entry in
                    try await ledger.createWishlistItem(entry.wishlistDraft(currencyCode: "CAD"), now: Self.now)
                }
            ).run()
        }
        #expect(probe.recorded.last == "write")
        #expect(try ModelContext(container).fetch(FetchDescriptor<WishlistItem>()).isEmpty)
    }

    @Test func theSiriWritesAreRefusedWhileARestoreRunsAndNothingIsInserted() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let board = TaskBoardService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: Self.now, now: Self.now)
        try await board.seedDefaultColumnsIfNeeded(now: Self.now)
        let context = ModelContext(container)
        let transactionsBefore = try context.fetchCount(FetchDescriptor<TransactionRecord>())
        let expense = TransactionDraft.quickAdd(
            amount: Money(minorUnits: 4_000, currencyCode: "CAD"), type: .expense, occurredAt: Self.now,
            categoryID: nil, description: "coffee", isAIClassified: false, accountID: nil)
        let wish = WishlistDraft(name: "headphones", estimatedPrice: Money(minorUnits: 14_900, currencyCode: "CAD"))
        let task = try TaskEntry.draft(text: "call the plumber", now: Self.now, calendar: Self.calendar)

        let gate = RestoreGate.shared(for: container)
        gate.beginRestore()
        #expect(gate.isRestoring)
        await #expect(throws: StoreWriteError.restoreInProgress) { try await ledger.create(expense, now: Self.now) }
        await #expect(throws: StoreWriteError.restoreInProgress) {
            try await ledger.createWishlistItem(wish, now: Self.now)
        }
        await #expect(throws: StoreWriteError.restoreInProgress) { try await board.createTask(task, now: Self.now) }
        gate.endRestore()

        #expect(try context.fetchCount(FetchDescriptor<TransactionRecord>()) == transactionsBefore)
        #expect(try context.fetch(FetchDescriptor<WishlistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)

        // Once the restore ends the same writes go through.
        try await ledger.create(expense, now: Self.now)
        try await ledger.createWishlistItem(wish, now: Self.now)
        try await board.createTask(task, now: Self.now)
        #expect(try context.fetchCount(FetchDescriptor<TransactionRecord>()) == transactionsBefore + 1)
        #expect(try context.fetch(FetchDescriptor<WishlistItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 1)
    }

    @Test func aRestoreMarksItselfRunningOnlyWhileItRuns() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let backup = BackupService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: Self.now, now: Self.now)
        let snapshot = try await backup.snapshot(now: Self.now, appVersion: "1.0") { _ in nil }
        _ = try await backup.restore(snapshot, availableMedia: [], now: Self.now)
        #expect(!RestoreGate.shared(for: container).isRestoring)
        let wish = WishlistDraft(name: "headphones", estimatedPrice: Money(minorUnits: 14_900, currencyCode: "CAD"))
        try await ledger.createWishlistItem(wish, now: Self.now)
        #expect(try ModelContext(container).fetch(FetchDescriptor<WishlistItem>()).count == 1)
    }
}
