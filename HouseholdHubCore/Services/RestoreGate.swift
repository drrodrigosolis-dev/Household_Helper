import Foundation
import SwiftData
import Synchronization

/// Why a write was refused without touching the store.
public enum StoreWriteError: Error, Equatable, Sendable {
    /// A restore is replacing the store; nothing else is written until it ends (§26.1).
    case restoreInProgress
}

/// Keeps the writes that can arrive from outside the app's screens (the Siri intents: a transaction, a wishlist item,
/// a task) out of a restore (Sprint 25).
///
/// The services are separate actors with their own contexts, so a flag on one actor can't be read atomically by
/// another. Instead there is one gate per container, shared by every service on it: `BackupService.restore` marks the
/// restore as running for its whole (synchronous) actor call, and a gated write runs its check, insert and save while
/// holding the same lock. A write therefore either finishes before the restore starts (which then replaces it like
/// any other record) or is refused with `StoreWriteError.restoreInProgress`; it never lands in the middle of one.
///
/// A gated body must be synchronous, must not await, and must not enter the gate again.
final class RestoreGate: Sendable {
    private static let gates = Mutex<[ObjectIdentifier: RestoreGate]>([:])

    /// Kept so the container, and with it this gate's key, lives as long as the gate.
    private let container: ModelContainer
    /// How many restores are running on the container.
    private let restores = Mutex(0)

    private init(container: ModelContainer) {
        self.container = container
    }

    static func shared(for container: ModelContainer) -> RestoreGate {
        gates.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let gate = RestoreGate(container: container)
            cache[ObjectIdentifier(container)] = gate
            return gate
        }
    }

    var isRestoring: Bool {
        restores.withLock { $0 > 0 }
    }

    /// Marks a restore as running. Waits for a gated write that is saving right now.
    func beginRestore() {
        restores.withLock { $0 += 1 }
    }

    func endRestore() {
        restores.withLock { $0 = max(0, $0 - 1) }
    }

    /// Runs `body` unless a restore is running, holding the gate so no restore starts until `body` returns.
    func write<T: Sendable>(_ body: () throws -> T) throws -> T {
        try restores.withLock { running in
            guard running == 0 else { throw StoreWriteError.restoreInProgress }
            return try body()
        }
    }
}
