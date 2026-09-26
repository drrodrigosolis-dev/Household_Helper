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
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var backupDocument: BackupFolderDocument?
    @State private var csvDocument: CSVDocument?
    @State private var isImporting = false
    /// What the file picker is choosing: a backup folder or a CSV file (Sprint 15). One picker serves both, since
    /// two `fileImporter`s on one view don't both work.
    @State private var importKind = ImportKind.backup
    @State private var csvImport: CSVImportSource?
    @State private var pendingRestore: PendingRestore?
    @State private var message: String?
    @State private var isWorking = false
    @State private var isRestoring = false
    private let calendar = HouseholdCalendar(timeZone: .current)

    enum ImportKind {
        case backup
        case csv
    }

    struct PendingRestore: Sendable {
        let backup: BackupDTO
        let media: [String: Data]
    }

    var body: some View {
        List {
            Section {
                Button("Back up now", systemImage: "externaldrive.badge.plus") { Task { await prepareBackup() } }
                    .accessibilityIdentifier("data.backup")
                Button("Restore from backup…", systemImage: "arrow.counterclockwise") {
                    importKind = .backup
                    isImporting = true
                }
                    .accessibilityIdentifier("data.restore")
            } header: {
                Text("Backup")
            } footer: {
                Text(
                    """
                    A backup is a folder with all your data and wishlist photos. It isn't encrypted, so keep it \
                    somewhere you trust. Restoring replaces everything.
                    """)
            }
            Section("Export") {
                Button("Export transactions as CSV", systemImage: "tablecells") { prepareCSV() }
                    .disabled(transactions.isEmpty)
                    .accessibilityIdentifier("data.csv")
            }
            Section {
                Button("Import transactions from CSV…", systemImage: "square.and.arrow.down") {
                    importKind = .csv
                    isImporting = true
                }
                .accessibilityIdentifier("data.importCSV")
            } header: {
                Text("Import")
            } footer: {
                Text("Pick a CSV file from your bank or a spreadsheet. You'll see every row before anything is saved.")
            }
            if let message {
                Text(message)
                    .accessibilityIdentifier("data.message")
            }
        }
        .disabled(isWorking)
        .navigationTitle("Data")
        .fullScreenCover(isPresented: $isRestoring) {
            ProgressView("Restoring…")
                .interactiveDismissDisabled()
        }
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importKind == .csv ? [.commaSeparatedText, .plainText] : [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            switch importKind {
            case .backup: Task { await load(url) }
            case .csv: Task { await loadCSV(url) }
            }
        }
        .sheet(item: $csvImport) { source in
            NavigationStack {
                CSVImportView(source: source) { count in
                    message = String(localized: "Imported \(count) transactions.")
                }
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

    private var flow: BackupFlow? {
        services.map { BackupFlow(service: $0.backup, images: $0.images) }
    }

    private func prepareBackup() async {
        guard let flow else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let prepared = try await flow.prepareBackup(now: .now, appVersion: AppInfo.version)
            if prepared.unreadablePhotos > 0 {
                let count = prepared.unreadablePhotos
                message = String(localized: "\(count) photos couldn't be read and are left out of this backup.")
            }
            backupDocument = BackupFolderDocument(backup: prepared.backup, media: prepared.media)
        } catch {
            message = String(localized: "The backup couldn't be prepared. Your data is unchanged.")
        }
    }

    // MARK: Restore

    /// Reads off the main actor: `backup.json` first, then only the files its manifest lists, within size limits.
    private func load(_ url: URL) async {
        isWorking = true
        defer { isWorking = false }
        let result = await Task.detached { () -> Result<PendingRestore, any Error> in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return Result {
                let read = try BackupFlow.read(folder: url)
                // Validate the whole file before offering to restore (spec §26.1); the restore checks again.
                try BackupValidator.validate(read.backup)
                return PendingRestore(backup: read.backup, media: read.media)
            }
        }.value
        switch result {
        case .success(let pending): pendingRestore = pending
        case .failure: message = String(localized: "That folder isn't a Household Hub backup this version can restore.")
        }
    }

    private func restoreMessage(_ backup: BackupDTO) -> String {
        let date = backup.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let count = backup.transactions.count
        let currency = backup.settings.currencyCode
        let contents = String(localized: "\(count) transactions, \(currency)")
        let replaced = String(localized: "Everything is replaced by the \(date) backup (\(contents)).")
        let photos = String(localized: "Wishlist photos are replaced too.")
        return [replaced, photos, String(localized: "This can't be undone.")].joined(separator: " ")
    }

    /// The app is covered while restoring, so no other screen writes or shows a record mid-restore.
    private func restore(_ pending: PendingRestore) async {
        guard let flow else { return }
        pendingRestore = nil
        isRestoring = true
        AppRouter.shared.isRestoring = true
        defer {
            isRestoring = false
            AppRouter.shared.isRestoring = false
        }
        do {
            let summary = try await flow.restore(pending.backup, media: pending.media, now: .now)
            if summary.missingMedia == 0 {
                message = String(localized: "Restored \(summary.transactions) transactions.")
            } else {
                message = String(localized: "Restored. \(summary.missingMedia) photos could not be restored.")
            }
        } catch {
            message = String(localized: "The restore failed. Your data is unchanged.")
        }
    }

    // MARK: CSV

    private func prepareCSV() {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = transactions.map { record in
            TransactionCSV.Row(
                occurredAt: record.occurredAt, type: record.type, status: record.status, amount: record.amount,
                category: record.categoryID.flatMap { names[$0] }, merchant: record.merchantNameSnapshot,
                notes: record.notes, account: record.accountID.flatMap { accountNames[$0] },
                toAccount: record.transferAccountID.flatMap { accountNames[$0] })
        }
        csvDocument = CSVDocument(text: TransactionCSV.text(rows, calendar: calendar))
    }

    /// Reads the picked file off the main actor, within the size limit, as UTF-8 (or Latin-1, which older bank
    /// exports use), and parses it. The preview does the rest; nothing is written here.
    private func loadCSV(_ url: URL) async {
        isWorking = true
        defer { isWorking = false }
        let result = await Task.detached { () -> Result<[[String]], any Error> in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return Result {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= CSVParser.maximumBytes else { throw CSVParser.Failure.tooLarge }
                let data = try Data(contentsOf: url)
                let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                guard let text = decoded else { throw CSVParser.Failure.empty }
                return try CSVParser.parse(text)
            }
        }.value
        switch result {
        case .success(let rows) where rows.count >= 2:
            csvImport = CSVImportSource(fileName: url.deletingPathExtension().lastPathComponent, rows: rows)
        case .success:
            message = String(localized: "That file has no rows to import.")
        case .failure(let error):
            message = Self.csvFailureMessage(error)
        }
    }

    private static func csvFailureMessage(_ error: any Error) -> String {
        switch error as? CSVParser.Failure {
        case .tooLarge:
            return String(localized: "That file is larger than 5 MB. Split it and import the parts.")
        case .tooManyRows(let limit):
            return String(localized: "That file has more than \(limit) rows. Split it and import the parts.")
        default:
            return String(localized: "That file couldn't be read as CSV.")
        }
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
