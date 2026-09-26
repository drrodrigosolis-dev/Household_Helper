import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct BackupTests {
    /// Whole seconds: backups keep milliseconds, and every date in the fixture derives from this.
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let zone = TimeZone(identifier: "America/Vancouver")!

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private struct Services {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let board: TaskBoardService
        let backup: BackupService

        func context() -> ModelContext { ModelContext(container) }
    }

    private func makeServices() throws -> Services {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        return Services(
            container: container, ledger: .make(container: container), categories: .make(container: container),
            board: .make(container: container), backup: .make(container: container))
    }

    /// One of everything: settings, categories, a merchant, a series with a posted occurrence, a purchase with a
    /// photo reference, board columns, a task linked to a wish, and a subtask.
    private func populate(_ services: Services) async throws {
        try await services.ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await services.categories.seedSystemCategoriesIfNeeded(now: now)
        try await services.board.seedDefaultColumnsIfNeeded(now: now)
        let draft = TransactionDraft(
            amount: cad(4_750), type: .expense, occurredAt: now.addingTimeInterval(-3_600), merchantName: "Café Luna",
            notes: "Beans, \"dark\" roast")
        try await services.ledger.create(draft, now: now)
        let start = now.addingTimeInterval(-40 * 86_400)
        let series = try await services.ledger.createSeries(
            templateAmount: cad(150_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: start,
            notes: "Rent", now: now)
        let occurrence = RecurrenceEngine().nextOccurrence(of: try seriesSnapshot(series, services), after: start)
        try await services.ledger.materialize(seriesID: series, occurrence: try #require(occurrence), now: now)
        let wish = try await services.ledger.createWishlistItem(
            WishlistDraft(name: "Lamp", estimatedPrice: cad(4_000), priority: .high), now: now)
        try await services.ledger.purchaseWishlistItem(
            wish, actualPrice: cad(3_799), occurredAt: now.addingTimeInterval(-60), categoryID: nil, now: now)
        try await services.ledger.setWishlistMedia("Wishlist/lamp.jpg", item: wish, now: now)
        let task = try await services.board.createTask(
            TaskDraft(title: "Hang lamp", notes: "Hallway", priority: .low, linkedWishlistItemID: wish), now: now)
        try await services.board.addSubtask(titled: "Buy hooks", to: task, now: now)
    }

    private func seriesSnapshot(_ id: UUID, _ services: Services) throws -> RecurringSeries {
        let models = try services.context().fetch(
            FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == id }))
        return try #require(models.first).series()
    }

    private func snapshot(_ services: Services, media: Set<String> = []) async throws -> BackupDTO {
        try await services.backup.snapshot(now: now, appVersion: "1.0") { reference in
            media.contains(reference) ? 1_234 : nil
        }
    }

    // MARK: Round trip

    @Test func exportRestoreRoundTripKeepsEveryRecordAndField() async throws {
        let source = try makeServices()
        try await populate(source)
        let exported = try await snapshot(source, media: ["Wishlist/lamp.jpg"])
        #expect(exported.transactions.count == 3)
        #expect(exported.mediaManifest == [BackupDTO.MediaEntry(reference: "Wishlist/lamp.jpg", sizeBytes: 1_234)])

        let json = try BackupDTO.encoder().encode(exported)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: json)
        #expect(decoded == exported)

        let target = try makeServices()
        let summary = try await target.backup.restore(decoded, availableMedia: ["Wishlist/lamp.jpg"], now: now)
        #expect(summary.transactions == 3)
        #expect(summary.missingMedia == 0)
        let again = try await snapshot(target, media: ["Wishlist/lamp.jpg"])
        #expect(again == exported)
    }

    @Test func restoredStoreStillWorksWithTheServices() async throws {
        let source = try makeServices()
        try await populate(source)
        let target = try makeServices()
        _ = try await target.backup.restore(try await snapshot(source), availableMedia: [], now: now)
        let calendar = HouseholdCalendar(timeZone: zone)
        let before = try await source.ledger.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        let after = try await target.ledger.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(after == before)
        // Exactly-once materialization survives the round trip.
        let series = try #require(try target.context().fetch(FetchDescriptor<RecurringTransaction>()).first)
        let records = try target.context().fetch(FetchDescriptor<TransactionRecord>())
        let posted = try #require(records.first { $0.recurringSeriesID != nil })
        let occurrence = try #require(posted.scheduledOccurrence)
        let seriesID = series.id
        await #expect(throws: LedgerError.alreadyMaterialized) {
            try await target.ledger.materialize(seriesID: seriesID, occurrence: occurrence, now: now)
        }
    }

    @Test func restoreReplacesExistingDataCompletely() async throws {
        let source = try makeServices()
        try await populate(source)
        let backup = try await snapshot(source)
        let target = try makeServices()
        try await populate(target)
        _ = try await target.backup.restore(backup, availableMedia: [], now: now)
        #expect(try target.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 3)
        #expect(try target.context().fetchCount(FetchDescriptor<AppSettings>()) == 1)
        #expect(try target.context().fetchCount(FetchDescriptor<BoardColumn>()) == 3)
    }

    @Test func missingMediaIsDroppedAndCounted() async throws {
        let source = try makeServices()
        try await populate(source)
        let backup = try await snapshot(source, media: ["Wishlist/lamp.jpg"])
        let target = try makeServices()
        let summary = try await target.backup.restore(backup, availableMedia: [], now: now)
        #expect(summary.missingMedia == 1)
        #expect(try target.context().fetch(FetchDescriptor<WishlistItem>()).first?.mediaReference == nil)
    }

    // MARK: Validation (spec §26.1: nothing is written unless the whole file is valid)

    @Test func invalidBackupsChangeNothing() async throws {
        let source = try makeServices()
        try await populate(source)
        let good = try await snapshot(source)
        var newer = good
        newer.schemaVersion = 2
        var dangling = good
        dangling.subtaskItems[0].taskID = UUID()
        var duplicate = good
        duplicate.categories.append(good.categories[0])
        var foreign = good
        foreign.transactions[0].currencyCode = "USD"
        var unreadable = good
        unreadable.transactions[0].status = "bogus"
        var zero = good
        zero.transactions[0].amountMinorUnits = 0
        var escaping = good
        escaping.wishlistItems[0].mediaReference = "../../secret.jpg"
        let cases: [(BackupDTO, BackupError)] = [
            (newer, .unsupportedSchemaVersion(2)),
            (dangling, .missingReference(entity: "subtaskItems", field: "taskID")),
            (duplicate, .duplicateID(entity: "categories")),
            (foreign, .currencyMismatch(entity: "transactions")),
            (unreadable, .invalidValue(entity: "transactions", field: "status", value: "bogus")),
            (zero, .invalidValue(entity: "transactions", field: "amountMinorUnits", value: "0")),
            (escaping, .invalidValue(entity: "wishlistItems", field: "mediaReference", value: "../../secret.jpg")),
        ]
        let target = try makeServices()
        try await target.ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await target.ledger.create(TransactionDraft(amount: cad(100), type: .expense, occurredAt: now), now: now)
        for (backup, expected) in cases {
            await #expect(throws: expected) {
                try await target.backup.restore(backup, availableMedia: [], now: now)
            }
        }
        #expect(try target.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 1)
        #expect(try target.context().fetchCount(FetchDescriptor<CategoryRecord>()) == 0)
    }

    @Test func aFolderWithoutBackupJSONIsNotABackup() {
        let folder = FileWrapper(directoryWithFileWrappers: ["notes.txt": FileWrapper(regularFileWithContents: Data())])
        #expect(throws: BackupError.notABackup) { try BackupPackage.read(folder) }
        let garbage = FileWrapper(directoryWithFileWrappers: [
            BackupPackage.jsonName: FileWrapper(regularFileWithContents: Data("{}".utf8))
        ])
        #expect(throws: BackupError.notABackup) { try BackupPackage.read(garbage) }
    }

    @Test func packageRoundTripCarriesJSONAndMedia() async throws {
        let source = try makeServices()
        try await populate(source)
        let backup = try await snapshot(source, media: ["Wishlist/lamp.jpg"])
        let image = Data([0xFF, 0xD8, 0xFF, 0x01])
        let folder = try BackupPackage.fileWrapper(for: backup) { $0 == "Wishlist/lamp.jpg" ? image : nil }
        let read = try BackupPackage.read(folder)
        #expect(read.backup == backup)
        #expect(read.media == ["Wishlist/lamp.jpg": image])
        let name = BackupPackage.folderName(for: now, calendar: HouseholdCalendar(timeZone: zone))
        #expect(name.hasPrefix("Household Hub Backup 20"))
    }

    // MARK: CSV

    @Test func csvQuotesAndGuardsAgainstFormulas() {
        let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "UTC")!)
        let rows = [
            TransactionCSV.Row(
                occurredAt: Date(timeIntervalSince1970: 0), type: .expense, status: .posted, amount: cad(4_750),
                category: "Dining", merchant: "Café, Luna", notes: "=HYPERLINK(\"x\")"),
            TransactionCSV.Row(
                occurredAt: Date(timeIntervalSince1970: 60), type: .income, status: .pending, amount: cad(120_000),
                category: nil, merchant: nil, notes: "line one\nline two"),
        ]
        let lines = TransactionCSV.text(rows, calendar: calendar).components(separatedBy: "\r\n")
        #expect(lines[0] == "Date,Type,Status,Amount,Currency,Category,Merchant,Notes")
        let first = "1970-01-01 00:00,expense,posted,-47.50,CAD,Dining,\"Café, Luna\",\"'=HYPERLINK(\"\"x\"\")\""
        #expect(lines[1] == first)
        #expect(lines[2] == "1970-01-01 00:01,income,pending,1200.00,CAD,,,\"line one\nline two\"")
    }
}
