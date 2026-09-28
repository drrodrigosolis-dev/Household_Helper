import Foundation

/// Sprint 23 (F6): a search text and filter kept under a name, re-applied from the top of Budget's filter menu.
struct SavedSearch: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var text: String
    var filter: TransactionFilter
}

/// Where saved searches are kept: `UserDefaults`, a device setting like the import presets, not app data — never in
/// SwiftData or a backup.
struct SavedSearchStore {
    static let key = "savedTransactionSearches"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every saved search, in the order saved. Corrupt or missing storage reads as none, never a crash.
    func all() -> [SavedSearch] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SavedSearch].self, from: data)) ?? []
    }

    /// Saves the search under a trimmed name; a search with the same name (ignoring case) is replaced where it was.
    /// Returns nil for an empty name.
    @discardableResult
    func save(name: String, text: String, filter: TransactionFilter) -> SavedSearch? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var searches = all()
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = SavedSearch(name: trimmed, text: words, filter: filter)
        if let index = searches.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            searches[index] = search
        } else {
            searches.append(search)
        }
        write(searches)
        return search
    }

    func delete(id: UUID) {
        write(all().filter { $0.id != id })
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }

    private func write(_ searches: [SavedSearch]) {
        guard let data = try? JSONEncoder().encode(searches) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The app's saved searches. UI tests start with none: what an earlier test run saved is forgotten once per launch.
@MainActor
enum SavedSearches {
    static let store: SavedSearchStore = {
        let store = SavedSearchStore()
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting) {
            store.removeAll()
        }
        return store
    }()
}
