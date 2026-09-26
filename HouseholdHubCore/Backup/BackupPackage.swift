import Foundation

/// The on-disk shape of a backup (Sprint 6 default 1): a folder with `backup.json` and `Media/<folder>/<file>` for
/// each image in the manifest. Built and read as `FileWrapper`s so the app can hand it to the Files app.
public enum BackupPackage {
    public static let jsonName = "backup.json"
    public static let mediaFolder = "Media"

    /// Folder wrapper holding the JSON and every manifest image that `mediaData` can supply.
    public static func fileWrapper(for backup: BackupDTO, mediaData: (String) -> Data?) throws -> FileWrapper {
        let json = try BackupDTO.encoder().encode(backup)
        var folders: [String: [String: FileWrapper]] = [:]
        for entry in backup.mediaManifest {
            let parts = entry.reference.split(separator: "/").map(String.init)
            guard parts.count == 2, let data = mediaData(entry.reference) else { continue }
            folders[parts[0], default: [:]][parts[1]] = FileWrapper(regularFileWithContents: data)
        }
        let subfolders = folders.mapValues { FileWrapper(directoryWithFileWrappers: $0) }
        let media = FileWrapper(directoryWithFileWrappers: subfolders)
        return FileWrapper(directoryWithFileWrappers: [
            jsonName: FileWrapper(regularFileWithContents: json),
            mediaFolder: media,
        ])
    }

    /// Reads a backup folder: the decoded DTO and the image data found for its manifest.
    public static func read(_ folder: FileWrapper) throws -> (backup: BackupDTO, media: [String: Data]) {
        guard folder.isDirectory, let json = folder.fileWrappers?[jsonName]?.regularFileContents else {
            throw BackupError.notABackup
        }
        let backup: BackupDTO
        do {
            backup = try BackupDTO.decoder().decode(BackupDTO.self, from: json)
        } catch {
            throw BackupError.notABackup
        }
        var media: [String: Data] = [:]
        let mediaRoot = folder.fileWrappers?[mediaFolder]?.fileWrappers ?? [:]
        for entry in backup.mediaManifest {
            let parts = entry.reference.split(separator: "/").map(String.init)
            guard parts.count == 2, let data = mediaRoot[parts[0]]?.fileWrappers?[parts[1]]?.regularFileContents
            else { continue }
            media[entry.reference] = data
        }
        return (backup, media)
    }

    /// "Household Hub Backup 2026-09-26" in the household calendar.
    public static func folderName(for date: Date, calendar: HouseholdCalendar) -> String {
        let parts = calendar.calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "Household Hub Backup \(day)"
    }
}

/// Transactions as CSV (Sprint 6 default 5): RFC 4180 quoting, and text cells that a spreadsheet would run as a
/// formula (`= + - @`) are prefixed with `'`.
public enum TransactionCSV {
    public struct Row: Sendable {
        public var occurredAt: Date
        public var type: TransactionType
        public var status: TransactionStatus
        public var amount: Money
        public var category: String?
        public var merchant: String?
        public var notes: String?

        public init(
            occurredAt: Date, type: TransactionType, status: TransactionStatus, amount: Money, category: String?,
            merchant: String?, notes: String?
        ) {
            self.occurredAt = occurredAt
            self.type = type
            self.status = status
            self.amount = amount
            self.category = category
            self.merchant = merchant
            self.notes = notes
        }
    }

    public static let header = ["Date", "Type", "Status", "Amount", "Currency", "Category", "Merchant", "Notes"]

    /// Amounts are signed decimals in major units ("-47.50"); dates are the household calendar day and time.
    public static func text(_ rows: [Row], calendar: HouseholdCalendar) -> String {
        var lines = [header.map(cell).joined(separator: ",")]
        for row in rows {
            let signed = row.type == .expense ? -row.amount.decimalValue : row.amount.decimalValue
            let digits = Currency.minorUnitDigits(forCode: row.amount.currencyCode)
            let amount = signed.formatted(
                .number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            let fields = [
                timestamp(row.occurredAt, calendar: calendar), row.type.rawValue, row.status.rawValue, amount,
                row.amount.currencyCode, row.category ?? "", row.merchant ?? "", row.notes ?? "",
            ]
            // The amount is a number the export itself wrote; only user text is guarded against formulas.
            let guarded = fields.enumerated().map { index, value in index == 3 ? value : formulaSafe(value) }
            lines.append(guarded.map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func formulaSafe(_ value: String) -> String {
        guard let first = value.first, "=+-@\t\r".contains(first) else { return value }
        return "'" + value
    }

    static func cell(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func timestamp(_ date: Date, calendar: HouseholdCalendar) -> String {
        let parts = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0,
            parts.minute ?? 0)
    }
}
