import HouseholdHubCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Data (spec §26, Sprint 6): back up everything to a folder, restore from one (replaces all data, after
/// confirming), and export transactions as CSV. Everything is user-triggered; nothing uploads anywhere.
struct DataView: View {
    @Environment(\.services) private var services
    @Query(sort: \TransactionRecord.occurredAt) private var transactions: [TransactionRecord]
    @Query private var categories: [CategoryRecord]

    @State private var backupDocument: BackupFolderDocument?
    @State private var csvDocument: CSVDocument?
    @State private var isImporting = false
    @State private var pendingRestore: PendingRestore?
    @State private var message: String?
    @State private var isWorking = false
    private let calendar = HouseholdCalendar(timeZone: .current)

    struct PendingRestore {
        let backup: BackupDTO
        let media: [String: Data]
    }

    var body: some View {
        List {
            Section {
                Button("Back up now", systemImage: "externaldrive.badge.plus") { Task { await prepareBackup() } }
                    .accessibilityIdentifier("data.backup")
                Button("Restore from backup…", systemImage: "arrow.counterclockwise") { isImporting = true }
                    .accessibilityIdentifier("data.restore")
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is a folder with all your data and wishlist photos. Restoring replaces everything.")
            }
            Section("Export") {
                Button("Export transactions as CSV", systemImage: "tablecells") { prepareCSV() }
                    .disabled(transactions.isEmpty)
                    .accessibilityIdentifier("data.csv")
            }
            if let message {
                Text(message)
                    .accessibilityIdentifier("data.message")
            }
        }
        .disabled(isWorking)
        .navigationTitle("Data")
        .fileExporter(
            isPresented: backupShown, document: backupDocument, contentType: .folder,
            defaultFilename: BackupPackage.folderName(for: .now, calendar: calendar)
        ) { result in
            report(result, saved: String(localized: "Backup saved."), failed: String(localized: "Backup not saved."))
        }
        .fileExporter(
            isPresented: csvShown, document: csvDocument, contentType: .commaSeparatedText,
            defaultFilename: "Household Hub Transactions"
        ) { result in
            report(result, saved: String(localized: "CSV saved."), failed: String(localized: "CSV not saved."))
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                load(url)
            }
        }
        .confirmationDialog(
            "Replace all data?", isPresented: restoreShown, titleVisibility: .visible, presenting: pendingRestore
        ) { pending in
            Button("Replace everything with this backup", role: .destructive) { Task { await restore(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(restoreMessage(pending.backup))
        }
    }

    // MARK: Backup

    private func prepareBackup() async {
        guard let services else { return }
        isWorking = true
        defer { isWorking = false }
        let images = services.images
        do {
            let backup = try await services.backup.snapshot(now: .now, appVersion: AppInfo.version) { reference in
                images?.fileSize(of: reference)
            }
            var media: [String: Data] = [:]
            for entry in backup.mediaManifest {
                media[entry.reference] = try? images?.data(for: entry.reference)
            }
            backupDocument = BackupFolderDocument(backup: backup, media: media)
        } catch {
            message = String(localized: "The backup couldn't be prepared. Your data is unchanged.")
        }
    }

    // MARK: Restore

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let folder = try FileWrapper(url: url, options: .immediate)
            let read = try BackupPackage.read(folder)
            // Validate the whole file before offering to restore (spec §26.1); the service checks again.
            try BackupValidator.validate(read.backup)
            pendingRestore = PendingRestore(backup: read.backup, media: read.media)
        } catch {
            message = String(localized: "That folder isn't a Household Hub backup this version can restore.")
        }
    }

    private func restoreMessage(_ backup: BackupDTO) -> String {
        let date = backup.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let count = backup.transactions.count
        return String(
            localized: "All data is replaced by the backup from \(date) (\(count) transactions). This can't be undone.")
    }

    /// Images first (a failed write leaves at worst an unreferenced file), then the store in one save, then images
    /// nothing refers to any more.
    private func restore(_ pending: PendingRestore) async {
        guard let services else { return }
        pendingRestore = nil
        isWorking = true
        defer { isWorking = false }
        var available = Set<String>()
        for (reference, data) in pending.media {
            if (try? services.images?.restore(data, as: reference)) != nil {
                available.insert(reference)
            }
        }
        do {
            let summary = try await services.backup.restore(pending.backup, availableMedia: available, now: .now)
            let kept = Set(pending.backup.wishlistItems.compactMap(\.mediaReference)).intersection(available)
            for reference in services.images?.references(in: .wishlist) ?? [] where !kept.contains(reference) {
                try? services.images?.delete(reference)
            }
            if summary.missingMedia == 0 {
                message = String(localized: "Restored \(summary.transactions) transactions.")
            } else {
                message = String(localized: "Restored. \(summary.missingMedia) photos were missing from the backup.")
            }
        } catch {
            message = String(localized: "The restore failed. Your data is unchanged.")
        }
    }

    // MARK: CSV

    private func prepareCSV() {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = transactions.map { record in
            TransactionCSV.Row(
                occurredAt: record.occurredAt, type: record.type, status: record.status, amount: record.amount,
                category: record.categoryID.flatMap { names[$0] }, merchant: record.merchantNameSnapshot,
                notes: record.notes)
        }
        csvDocument = CSVDocument(text: TransactionCSV.text(rows, calendar: calendar))
    }

    // MARK: Presentation

    private func report(_ result: Result<URL, any Error>, saved: String, failed: String) {
        switch result {
        case .success: message = saved
        case .failure: message = failed
        }
    }

    private var backupShown: Binding<Bool> {
        Binding(get: { backupDocument != nil }, set: { if !$0 { backupDocument = nil } })
    }

    private var csvShown: Binding<Bool> {
        Binding(get: { csvDocument != nil }, set: { if !$0 { csvDocument = nil } })
    }

    private var restoreShown: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }
}

/// A backup folder for the Files app. Holds plain values (Sendable) and builds the wrapper when asked.
struct BackupFolderDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    let backup: BackupDTO
    let media: [String: Data]

    init(backup: BackupDTO, media: [String: Data]) {
        self.backup = backup
        self.media = media
    }

    init(configuration: ReadConfiguration) throws {
        let read = try BackupPackage.read(configuration.file)
        backup = read.backup
        media = read.media
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try BackupPackage.fileWrapper(for: backup) { media[$0] }
    }
}

struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
