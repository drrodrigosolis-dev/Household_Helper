import Foundation

/// A saved column mapping for one bank's CSV export (Sprint 23, F8), so a later file from the same bank can be
/// mapped automatically instead of by hand every time. A device setting like the fun theme (`ThemeSettings`): stored
/// in `UserDefaults` via `CSVImportPresetStore`, never in SwiftData or a backup.
public struct CSVImportPreset: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var columns: [CSVColumnRole: Int]
    public var dateFormat: CSVDateFormat
    public var decimalMark: Character
    public var spendingIsPositive: Bool
    /// The account this preset files transactions into. Applying the preset ignores it when the account is archived
    /// or no longer exists (`targetAccountID(activeAccountIDs:)`); the import flow's own default applies instead.
    public var accountID: UUID
    /// The file's header names, as they were when the preset was saved: what a later file is matched against
    /// (`matches(header:)`).
    public var headerSignature: [String]

    public init(
        id: UUID = UUID(), name: String, columns: [CSVColumnRole: Int], dateFormat: CSVDateFormat,
        decimalMark: Character, spendingIsPositive: Bool, accountID: UUID, headerSignature: [String]
    ) {
        self.id = id
        self.name = name
        self.columns = columns
        self.dateFormat = dateFormat
        self.decimalMark = decimalMark
        self.spendingIsPositive = spendingIsPositive
        self.accountID = accountID
        self.headerSignature = headerSignature
    }

    /// This preset's mapping, ready for `CSVImportPlanner.preview`.
    public var mapping: CSVMapping {
        CSVMapping(
            columns: columns, dateFormat: dateFormat, decimalMark: decimalMark,
            spendingIsPositive: spendingIsPositive)
    }

    /// Whether a file with this header should offer this preset: the same names in the same order (so column
    /// indices still line up), ignoring case and surrounding whitespace.
    public func matches(header: [String]) -> Bool {
        Self.normalize(header) == Self.normalize(headerSignature)
    }

    /// `accountID`, unless it no longer names an active account (archived or deleted), in which case nil: the
    /// import flow's own default account applies instead of guessing another one.
    public func targetAccountID(activeAccountIDs: Set<UUID>) -> UUID? {
        activeAccountIDs.contains(accountID) ? accountID : nil
    }

    private static func normalize(_ header: [String]) -> [String] {
        header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
}

extension CSVImportPreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, columns, dateFormat, decimalMark, spendingIsPositive, accountID, headerSignature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let rawColumns = try container.decode([String: Int].self, forKey: .columns)
        columns = Dictionary(
            uniqueKeysWithValues: rawColumns.compactMap { key, value in
                CSVColumnRole(rawValue: key).map { ($0, value) }
            })
        dateFormat = try container.decode(CSVDateFormat.self, forKey: .dateFormat)
        let mark = try container.decode(String.self, forKey: .decimalMark)
        decimalMark = mark.first ?? "."
        spendingIsPositive = try container.decode(Bool.self, forKey: .spendingIsPositive)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        headerSignature = try container.decode([String].self, forKey: .headerSignature)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        let rawColumns = Dictionary(uniqueKeysWithValues: columns.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawColumns, forKey: .columns)
        try container.encode(dateFormat, forKey: .dateFormat)
        try container.encode(String(decimalMark), forKey: .decimalMark)
        try container.encode(spendingIsPositive, forKey: .spendingIsPositive)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(headerSignature, forKey: .headerSignature)
    }
}

/// Where CSV import presets are kept (Sprint 23, F8): `UserDefaults`, a device setting, not app data — never read or
/// written by backup/restore.
public struct CSVImportPresetStore: Sendable {
    /// UserDefaults is documented as thread-safe but isn't marked Sendable in the SDK (CI run 36379230728).
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key = "csvImportPresets"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every saved preset. Corrupt or missing storage reads as no presets, never a crash.
    public func all() -> [CSVImportPreset] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CSVImportPreset].self, from: data)) ?? []
    }

    /// Adds a new preset, or replaces the one with the same id.
    public func save(_ preset: CSVImportPreset) {
        var presets = all()
        presets.removeAll { $0.id == preset.id }
        presets.append(preset)
        write(presets)
    }

    public func delete(id: UUID) {
        write(all().filter { $0.id != id })
    }

    /// The first saved preset whose header signature matches, if any.
    public func matching(header: [String]) -> CSVImportPreset? {
        all().first { $0.matches(header: header) }
    }

    private func write(_ presets: [CSVImportPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
