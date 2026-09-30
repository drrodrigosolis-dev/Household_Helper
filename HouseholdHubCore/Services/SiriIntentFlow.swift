import Foundation

/// Why a Siri intent stopped before writing (Sprint 25). Nothing is saved in either case.
public enum SiriIntentFlowError: Error, Equatable, Sendable {
    /// A restore is running: before the prompt, after it, or when the write is made.
    case restoring
    /// The app lock is on and the person didn't unlock.
    case locked
}

/// The order every Siri write follows (Sprint 25), kept out of the App Intents so it is unit-tested. The intents
/// supply each step as a closure and only turn the outcome into their own dialogs and errors.
///
/// 1. No restore is running.
/// 2. The app lock: the person unlocks, or the lock is off. A locked app never reads the sentence, so the on-device
///    model is never asked.
/// 3. The draft: the grammar, refined by the model where it is on (`SiriRefinement`).
/// 4. The person confirms it (`requestConfirmation`). A declined prompt throws, so nothing is written.
/// 5. No restore started while the prompt was showing.
/// 6. The write, exactly once. The services refuse it too if a restore starts after step 5 (`RestoreGate`).
public struct SiriIntentFlow<Draft> {
    /// Whether a restore is replacing the store (`AppRouter.isRestoring` in the app).
    public var isRestoring: () async -> Bool
    /// True when the app lock is off or the person unlocked.
    public var unlock: () async throws -> Bool
    public var draft: () async throws -> Draft
    /// Shows `Draft` for the person to confirm; throws when they decline.
    public var confirm: (Draft) async throws -> Void
    public var write: (Draft) async throws -> Void

    public init(
        isRestoring: @escaping () async -> Bool, unlock: @escaping () async throws -> Bool,
        draft: @escaping () async throws -> Draft, confirm: @escaping (Draft) async throws -> Void,
        write: @escaping (Draft) async throws -> Void
    ) {
        self.isRestoring = isRestoring
        self.unlock = unlock
        self.draft = draft
        self.confirm = confirm
        self.write = write
    }

    /// Runs the steps in order and returns the draft that was written. Errors from `draft`, `confirm` and `write`
    /// pass through unchanged, except a write refused by a restore, which is `SiriIntentFlowError.restoring`.
    @discardableResult
    public func run() async throws -> Draft {
        guard !(await isRestoring()) else { throw SiriIntentFlowError.restoring }
        guard try await unlock() else { throw SiriIntentFlowError.locked }
        let draft = try await self.draft()
        try await confirm(draft)
        // A restore may have started while the prompt was showing; nothing else writes during one.
        guard !(await isRestoring()) else { throw SiriIntentFlowError.restoring }
        do {
            try await write(draft)
        } catch StoreWriteError.restoreInProgress {
            throw SiriIntentFlowError.restoring
        }
        return draft
    }
}
