import Foundation

/// The portable backup format, v2 (spec §26; v2 adds accounts and transfers, Sprint 10). v1 files still read:
/// `upgradedToCurrent()` turns one into v2 before anything validates or restores it. Plain Codable values with every
/// stored field of every model; money in integer minor units, dates ISO 8601, enums as their raw strings, recurrence
/// rules as JSON objects. Image bytes are never inline: `mediaManifest` lists the files that travel next to
/// `backup.json` (§26.1).
public struct BackupDTO: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    /// Versions this app reads; older ones are upgraded on the way in.
    public static let readableSchemaVersions: ClosedRange<Int> = 1...2

    public var schemaVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var settings: Settings
    public var categories: [Category]
    public var merchants: [MerchantDTO]
    public var transactions: [Transaction]
    public var recurringTransactions: [Recurring]
    public var wishlistItems: [Wish]
    public var boardColumns: [Column]
    public var taskItems: [TaskDTO]
    public var subtaskItems: [Subtask]
    public var mediaManifest: [MediaEntry]
    /// v2. Absent in v1 files, where the one household baseline lived in `settings`.
    public var accounts: [AccountDTO]?
    /// Category budgets (Sprint 11). Absent in older files, which restore with none.
    public var budgets: [BudgetDTO]?

    /// AppSettings minus anything secret (there are no secrets in the store; tokens live in the Keychain, §7.11).
    public struct Settings: Codable, Equatable, Sendable {
        public var id: UUID
        public var currencyCode: String
        public var onboardingCompleted: Bool
        /// v1 only: the single household baseline, which v2 keeps on the accounts.
        public var startingBalanceMinorUnits: Int64?
        public var startingBalanceDate: Date?
        /// v2: where new entries go.
        public var defaultAccountID: UUID?
        public var includePendingInProjection: Bool
        public var defaultAnalyticsPeriod: String
        /// Optional in the file so v1 backups written before these switches existed still read (absent = the default,
        /// on).
        public var aiCategorizationEnabled: Bool?
        public var naturalLanguageEnabled: Bool?
        public var aiInsightsEnabled: Bool?
        /// Optional for the same reason (absent = on, the default).
        public var widgetShowsBalance: Bool?
        /// Absent = off.
        public var analyticsIncludesPending: Bool?
        /// Optional for the same reason (absent = default: system theme, app accent, Expense).
        public var selectedTheme: String?
        public var accentColorHex: String?
        public var defaultQuickAddType: String?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Category: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var icon: String
        public var color: ColorToken
        public var kind: String
        public var sortOrder: Int
        public var isSystem: Bool
        public var isArchived: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct MerchantDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var displayName: String
        public var defaultCategoryID: UUID?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Transaction: Codable, Equatable, Sendable {
        public var id: UUID
        public var amountMinorUnits: Int64
        public var currencyCode: String
        public var type: String
        public var status: String
        public var source: String
        public var occurredAt: Date
        public var merchantID: UUID?
        public var merchantNameSnapshot: String?
        public var categoryID: UUID?
        public var notes: String?
        public var recurringSeriesID: UUID?
        public var scheduledOccurrence: Date?
        public var wishlistItemID: UUID?
        public var isAIClassified: Bool
        /// v2; required once upgraded.
        public var accountID: UUID?
        public var transferAccountID: UUID?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Recurring: Codable, Equatable, Sendable {
        public var id: UUID
        public var templateAmountMinorUnits: Int64
        public var currencyCode: String
        public var type: String
        public var categoryID: UUID?
        public var merchantID: UUID?
        public var notes: String?
        public var rule: RecurrenceRule
        public var timeZoneIdentifier: String
        public var startDate: Date
        public var endDate: Date?
        public var nextOccurrence: Date?
        public var isEnabled: Bool
        /// v2; required once upgraded.
        public var accountID: UUID?
        public var transferAccountID: UUID?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct BudgetDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var categoryID: UUID
        public var limitMinorUnits: Int64
        public var currencyCode: String
        public var rollsOver: Bool
        public var startMonth: Date
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct AccountDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var kind: String
        public var currencyCode: String
        public var startingBalanceMinorUnits: Int64
        public var startingBalanceDate: Date
        public var sortOrder: Int
        public var isArchived: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Wish: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var estimatedPriceMinorUnits: Int64
        public var actualPriceMinorUnits: Int64?
        public var currencyCode: String
        public var priority: String
        public var status: String
        public var categoryID: UUID?
        public var notes: String?
        public var mediaReference: String?
        public var linkedTaskID: UUID?
        public var purchasedTransactionID: UUID?
        public var targetDate: Date?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Column: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var sortOrder: Int
        public var isSystem: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct TaskDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var notes: String?
        public var columnID: UUID
        public var priority: String
        public var dueDate: Date?
        public var completedAt: Date?
        public var sortOrder: Double
        public var linkedWishlistItemID: UUID?
        public var linkedTransactionID: UUID?
        public var archivedAt: Date?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Subtask: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var isCompleted: Bool
        public var sortOrder: Double
        public var taskID: UUID
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct MediaEntry: Codable, Equatable, Sendable {
        public var reference: String
        public var sizeBytes: Int
    }

    // MARK: Encoding

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, container in
            var single = container.singleValueContainer()
            try single.encode(date.formatted(Self.dateStyle))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            let text = try single.decode(String.self)
            do {
                return try Self.dateStyle.parse(text)
            } catch {
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "Not an ISO 8601 date: \(text)")
            }
        }
        return decoder
    }

    /// ISO 8601 in UTC with milliseconds. A round trip keeps timestamps to the millisecond; recurrence occurrences
    /// and calendar days are whole seconds, so comparisons that matter survive exactly.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

extension BackupDTO {
    /// The same backup in the current format. A v1 file had one household baseline in its settings; it becomes the
    /// first account, "Main account", which gets the settings row's id (so every read of the same file produces the
    /// same account) and holds every transaction and recurring item. A v2 file is returned as it is.
    public func upgradedToCurrent() -> BackupDTO {
        guard schemaVersion == 1 else { return self }
        var upgraded = self
        let main = AccountDTO(
            id: settings.id, name: TransactionService.mainAccountName, kind: AccountKind.bank.rawValue,
            currencyCode: settings.currencyCode,
            startingBalanceMinorUnits: settings.startingBalanceMinorUnits ?? 0,
            startingBalanceDate: settings.startingBalanceDate ?? settings.createdAt, sortOrder: 0, isArchived: false,
            createdAt: settings.createdAt, updatedAt: settings.updatedAt)
        upgraded.schemaVersion = 2
        upgraded.accounts = [main]
        upgraded.settings.defaultAccountID = main.id
        upgraded.settings.startingBalanceMinorUnits = nil
        upgraded.settings.startingBalanceDate = nil
        upgraded.transactions = transactions.map { record in
            var copy = record
            copy.accountID = copy.accountID ?? main.id
            return copy
        }
        upgraded.recurringTransactions = recurringTransactions.map { item in
            var copy = item
            copy.accountID = copy.accountID ?? main.id
            return copy
        }
        return upgraded
    }
}
