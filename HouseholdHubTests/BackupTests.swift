import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import HouseholdHubCore

struct BackupTests {
    /// Whole seconds: backups keep milliseconds, and every date in the fixture derives from this.
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private static let lamp = "Wishlist/5B3C3D0E-7C2A-4F57-9E7B-2A1D6C9F0B11.jpg"

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
        try await services.ledger.setWishlistMedia(Self.lamp, item: wish, now: now)
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

    /// Phase 10 review open question: other services' contexts may hold objects the restore replaced. A write
    /// through one of them afterwards must not bring back the pre-restore values.
    @Test func writesAfterRestoringThisDevicesBackupKeepTheRestoredValues() async throws {
        let services = try makeServices()
        try await populate(services)
        try await services.ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(10_000), asOf: now, now: now)
        let backup = try await snapshot(services)
        // Change things after the backup, through the same services that will write after the restore.
        try await services.ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(99_999), asOf: now, now: now)
        try await services.ledger.setIncludePendingInProjection(true, now: now)
        _ = try await services.backup.restore(backup, availableMedia: [], now: now)

        try await services.ledger.setWidgetShowsBalance(false, now: now)
        let settings = try #require(try services.context().fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.startingBalanceMinorUnits == 10_000)
        #expect(settings.includePendingInProjection == backup.settings.includePendingInProjection)
        #expect(settings.widgetShowsBalance == false)
        let snapshotAfter = try await services.ledger.settingsSnapshot()
        #expect(snapshotAfter?.startingBalance == cad(10_000))
    }

    @Test func exportRestoreRoundTripKeepsEveryRecordAndField() async throws {
        let source = try makeServices()
        try await populate(source)
        let exported = try await snapshot(source, media: [Self.lamp])
        #expect(exported.transactions.count == 3)
        #expect(exported.mediaManifest == [BackupDTO.MediaEntry(reference: Self.lamp, sizeBytes: 1_234)])

        let json = try BackupDTO.encoder().encode(exported)
        let decoded = try BackupDTO.decoder().decode(BackupDTO.self, from: json)
        #expect(decoded == exported)

        let target = try makeServices()
        let summary = try await target.backup.restore(decoded, availableMedia: [Self.lamp], now: now)
        #expect(summary.transactions == 3)
        #expect(summary.missingMedia == 0)
        let again = try await snapshot(target, media: [Self.lamp])
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
        let backup = try await snapshot(source, media: [Self.lamp])
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
        let backup = try await snapshot(source, media: [Self.lamp])
        let image = Data([0xFF, 0xD8, 0xFF, 0x01])
        let folder = try BackupPackage.fileWrapper(for: backup) { $0 == Self.lamp ? image : nil }
        let read = try BackupPackage.read(folder)
        #expect(read.backup == backup)
        #expect(read.media == [Self.lamp: image])
        let name = BackupPackage.folderName(for: now, calendar: HouseholdCalendar(timeZone: zone))
        #expect(name.hasPrefix("Household Hub Backup 20"))
    }

    // MARK: Restore over the same ids (the everyday case: restoring this device's own backup)

    @Test func restoringOwnBackupAfterChangesBringsBackExactlyTheBackup() async throws {
        let services = try makeServices()
        try await populate(services)
        let backup = try await snapshot(services)
        // Change things after the backup: add, edit, and delete records with the same ids still around.
        try await services.ledger.create(TransactionDraft(amount: cad(999), type: .expense, occurredAt: now), now: now)
        let category = try #require(try services.context().fetch(FetchDescriptor<CategoryRecord>()).first)
        try await services.categories.update(
            category: category.id, name: "Renamed", icon: category.icon, color: category.color, kind: category.kind,
            now: now)
        let task = try #require(try services.context().fetch(FetchDescriptor<TaskItem>()).first)
        try await services.board.deleteTask(task.id)
        _ = try await services.backup.restore(backup, availableMedia: [Self.lamp], now: now)
        let again = try await snapshot(services)
        #expect(again == backup)
    }

    // MARK: Link invariants (spec §8.1 and the services' rules)

    @Test func purchaseLinksMustAgreeBothWays() async throws {
        let source = try makeServices()
        try await populate(source)
        let good = try await snapshot(source)
        let purchase = try #require(good.transactions.first { $0.wishlistItemID != nil })
        var twoWishes = good
        var copy = try #require(good.wishlistItems.first)
        copy.id = UUID()
        copy.mediaReference = nil
        twoWishes.wishlistItems.append(copy)
        var income = good
        income.transactions = good.transactions.map { record in
            var changed = record
            if record.id == purchase.id {
                changed.type = TransactionType.income.rawValue
                changed.categoryID = nil
            }
            return changed
        }
        var unlinked = good
        unlinked.transactions = good.transactions.map { record in
            var changed = record
            changed.wishlistItemID = nil
            return changed
        }
        var purchasedNoLink = unlinked
        purchasedNoLink.wishlistItems = good.wishlistItems.map { wish in
            var changed = wish
            changed.purchasedTransactionID = nil
            return changed
        }
        let cases: [(BackupDTO, BackupError)] = [
            (twoWishes, .inconsistentLink(entity: "wishlistItems", field: "purchasedTransactionID")),
            (income, .inconsistentLink(entity: "wishlistItems", field: "purchasedTransactionID")),
            (unlinked, .inconsistentLink(entity: "wishlistItems", field: "purchasedTransactionID")),
            (purchasedNoLink, .inconsistentLink(entity: "wishlistItems", field: "status")),
        ]
        for (backup, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(backup) }
        }
    }

    @Test func serviceRulesAreValidated() async throws {
        let source = try makeServices()
        try await populate(source)
        let good = try await snapshot(source)
        let salary = try #require(good.categories.first { $0.name == "Salary" })
        var wrongKind = good
        wrongKind.transactions[0].categoryID = salary.id
        wrongKind.transactions[0].type = TransactionType.expense.rawValue
        var openInDone = good
        let done = try #require(good.boardColumns.max { $0.sortOrder < $1.sortOrder })
        openInDone.taskItems[0].columnID = done.id
        openInDone.taskItems[0].completedAt = nil
        var orphanOccurrence = good
        let recurring = try #require(good.transactions.firstIndex { $0.recurringSeriesID != nil })
        orphanOccurrence.transactions[recurring].scheduledOccurrence = nil
        var sharedPhoto = good
        let entry = BackupDTO.MediaEntry(reference: Self.lamp, sizeBytes: 1)
        sharedPhoto.mediaManifest = [entry, entry]
        var thumbnail = good
        thumbnail.wishlistItems[0].mediaReference = "Wishlist/5B3C3D0E-7C2A-4F57-9E7B-2A1D6C9F0B11-thumb.jpg"
        let cases: [(BackupDTO, BackupError)] = [
            (wrongKind, .inconsistentLink(entity: "transactions", field: "categoryID")),
            (openInDone, .inconsistentLink(entity: "taskItems", field: "completedAt")),
            (orphanOccurrence, .inconsistentLink(entity: "transactions", field: "recurringSeriesID")),
            (sharedPhoto, .duplicateID(entity: "mediaManifest")),
            (
                thumbnail,
                .invalidValue(
                    entity: "wishlistItems", field: "mediaReference",
                    value: "Wishlist/5B3C3D0E-7C2A-4F57-9E7B-2A1D6C9F0B11-thumb.jpg")
            ),
        ]
        for (backup, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(backup) }
        }
        try BackupValidator.validate(good)
    }

    // MARK: Files (BackupFlow with a real image store in a temporary folder)

    private func imageStore() -> ImageStore {
        ImageStore(root: FileManager.default.temporaryDirectory.appending(path: "BackupTests-\(UUID().uuidString)"))
    }

    private func jpeg(_ store: ImageStore) throws -> Data {
        let png = try #require(Data(base64Encoded: Self.tinyPNG))
        let reference = try store.save(png, in: .wishlist)
        return try store.data(for: reference)
    }

    /// 1×1 PNG.
    private static let tinyPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    @Test func restoreWritesPhotosAndRemovesFilesNothingReferences() async throws {
        let source = try makeServices()
        try await populate(source)
        let images = imageStore()
        let photo = try jpeg(images)
        let stray = try images.save(try #require(Data(base64Encoded: Self.tinyPNG)), in: .wishlist)
        let backup = try await snapshot(source, media: [Self.lamp])
        let flow = BackupFlow(service: try makeServices().backup, images: images)
        let summary = try await flow.restore(backup, media: [Self.lamp: photo], now: now)
        #expect(summary.missingMedia == 0)
        #expect(images.fileSize(of: Self.lamp) != nil)
        #expect(images.fileSize(of: stray) == nil, "A file nothing refers to after the restore is removed")
        #expect(images.references(in: .wishlist).count == 1)
    }

    /// Phase 10 review B1: the backup's copy of a photo can't be read, but the device already has the same file.
    @Test func restoreKeepsAPhotoTheDeviceAlreadyHasWhenTheBackupCopyIsUnreadable() async throws {
        let source = try makeServices()
        try await populate(source)
        let images = imageStore()
        try images.restore(try jpeg(imageStore()), as: Self.lamp)
        let backup = try await snapshot(source, media: [Self.lamp])
        let flow = BackupFlow(service: try makeServices().backup, images: images)
        let summary = try await flow.restore(backup, media: [:], now: now)
        #expect(summary.missingMedia == 0)
        #expect(images.fileSize(of: Self.lamp) != nil, "The intact local photo must survive the restore")
    }

    @Test func failedRestoreLeavesPhotosAsTheyWere() async throws {
        let target = try makeServices()
        try await target.ledger.ensureSettings(currencyCode: "CAD", now: now)
        let images = imageStore()
        let existing = try images.save(try #require(Data(base64Encoded: Self.tinyPNG)), in: .wishlist)
        let wish = try await target.ledger.createWishlistItem(
            WishlistDraft(name: "Chair", estimatedPrice: cad(100)), now: now)
        try await target.ledger.setWishlistMedia(existing, item: wish, now: now)
        let source = try makeServices()
        try await populate(source)
        var bad = try await snapshot(source, media: [Self.lamp])
        bad.subtaskItems[0].taskID = UUID()
        let flow = BackupFlow(service: target.backup, images: images)
        await #expect(throws: BackupError.missingReference(entity: "subtaskItems", field: "taskID")) {
            try await flow.restore(bad, media: [Self.lamp: try jpeg(imageStore())], now: now)
        }
        #expect(images.references(in: .wishlist) == [existing])
    }

    @Test func exportLeavesOutUnreadablePhotosAndSaysSo() async throws {
        let services = try makeServices()
        try await populate(services)
        let flow = BackupFlow(service: services.backup, images: imageStore())
        let prepared = try await flow.prepareBackup(now: now, appVersion: "1.0")
        #expect(prepared.backup.mediaManifest.isEmpty)
        #expect(prepared.unreadablePhotos == 1)
    }

    @Test func readingAFolderLoadsOnlyListedFilesOfTheRecordedSize() async throws {
        let source = try makeServices()
        try await populate(source)
        let photo = try jpeg(imageStore())
        var backup = try await snapshot(source, media: [Self.lamp])
        backup.mediaManifest = [BackupDTO.MediaEntry(reference: Self.lamp, sizeBytes: photo.count)]
        let folder = FileManager.default.temporaryDirectory.appending(path: "BackupFolder-\(UUID().uuidString)")
        let wrapper = try BackupPackage.fileWrapper(for: backup) { $0 == Self.lamp ? photo : nil }
        try wrapper.write(to: folder, options: .atomic, originalContentsURL: nil)
        let read = try BackupFlow.read(folder: folder)
        #expect(read.backup == backup)
        #expect(read.media == [Self.lamp: photo])

        backup.mediaManifest = [BackupDTO.MediaEntry(reference: Self.lamp, sizeBytes: photo.count + 1)]
        let mismatched = FileManager.default.temporaryDirectory.appending(path: "BackupFolder-\(UUID().uuidString)")
        try BackupPackage.fileWrapper(for: backup) { $0 == Self.lamp ? photo : nil }
            .write(to: mismatched, options: .atomic, originalContentsURL: nil)
        #expect(try BackupFlow.read(folder: mismatched).media.isEmpty, "A file whose size differs is not trusted")
        let empty = FileManager.default.temporaryDirectory.appending(path: "Empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: BackupError.notABackup) { try BackupFlow.read(folder: empty) }
    }

    /// Security review: a folder is validated before any image is read, and all images together stay under a cap.
    @Test func readingAFolderValidatesFirstAndCapsTotalImageBytes() async throws {
        let source = try makeServices()
        try await populate(source)
        let photo = try jpeg(imageStore())
        var backup = try await snapshot(source, media: [Self.lamp])
        backup.mediaManifest = [BackupDTO.MediaEntry(reference: Self.lamp, sizeBytes: photo.count)]
        let folder = FileManager.default.temporaryDirectory.appending(path: "BackupFolder-\(UUID().uuidString)")
        try BackupPackage.fileWrapper(for: backup) { $0 == Self.lamp ? photo : nil }
            .write(to: folder, options: .atomic, originalContentsURL: nil)
        #expect(throws: BackupError.tooLarge(BackupPackage.mediaFolder)) {
            try BackupFlow.read(folder: folder, mediaLimit: photo.count - 1)
        }
        #expect(try BackupFlow.read(folder: folder, mediaLimit: photo.count).media == [Self.lamp: photo])

        let unlisted = "Wishlist/0E6F1B7A-2C3D-4E5F-8A9B-0C1D2E3F4A5B.jpg"
        backup.mediaManifest.append(BackupDTO.MediaEntry(reference: unlisted, sizeBytes: photo.count))
        let invalid = FileManager.default.temporaryDirectory.appending(path: "BackupFolder-\(UUID().uuidString)")
        try BackupPackage.fileWrapper(for: backup) { _ in photo }
            .write(to: invalid, options: .atomic, originalContentsURL: nil)
        #expect(throws: BackupError.inconsistentLink(entity: "mediaManifest", field: "reference")) {
            try BackupFlow.read(folder: invalid)
        }
    }

    /// Security review: a restored photo is re-encoded like a new one rather than written byte for byte.
    @Test func restoredPhotosAreReencodedAsJPEG() throws {
        let images = imageStore()
        try images.restore(try #require(Data(base64Encoded: Self.tinyPNG)), as: Self.lamp)
        let stored = try images.data(for: Self.lamp)
        let source = try #require(CGImageSourceCreateWithData(stored as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    // MARK: Format v1 fixture

    /// A hand-written v1 file: if a later change breaks reading v1 backups, this fails.
    @Test func versionOneFixtureDecodesAndValidates() throws {
        let json = """
            {
              "appVersion": "1.0", "exportedAt": "2026-09-26T10:00:00.000Z", "schemaVersion": 1,
              "settings": {
                "id": "11111111-1111-1111-1111-111111111111", "currencyCode": "CAD", "onboardingCompleted": true,
                "startingBalanceMinorUnits": 10000, "startingBalanceDate": "2026-09-01T07:00:00.000Z",
                "includePendingInProjection": false, "defaultAnalyticsPeriod": "thisMonth",
                "createdAt": "2026-09-01T07:00:00.000Z", "updatedAt": "2026-09-01T07:00:00.000Z"
              },
              "categories": [{
                "id": "22222222-2222-2222-2222-222222222222", "name": "Dining", "icon": "fork.knife",
                "color": {"red": 198, "green": 40, "blue": 40, "alpha": 255}, "kind": "expense", "sortOrder": 0,
                "isSystem": true, "isArchived": false,
                "createdAt": "2026-09-01T07:00:00.000Z", "updatedAt": "2026-09-01T07:00:00.000Z"
              }],
              "merchants": [],
              "transactions": [{
                "id": "33333333-3333-3333-3333-333333333333", "amountMinorUnits": 4750, "currencyCode": "CAD",
                "type": "expense", "status": "posted", "source": "manual", "occurredAt": "2026-09-20T18:30:00.000Z",
                "categoryID": "22222222-2222-2222-2222-222222222222", "notes": "coffee", "isAIClassified": false,
                "createdAt": "2026-09-20T18:30:00.000Z", "updatedAt": "2026-09-20T18:30:00.000Z"
              }],
              "recurringTransactions": [], "wishlistItems": [], "boardColumns": [], "taskItems": [],
              "subtaskItems": [], "mediaManifest": []
            }
            """
        let backup = try BackupDTO.decoder().decode(BackupDTO.self, from: Data(json.utf8))
        try BackupValidator.validate(backup)
        #expect(backup.transactions.first?.amountMinorUnits == 4_750)
        #expect(backup.settings.startingBalanceMinorUnits == 10_000)
    }

    // MARK: CSV

    static let cellCases: [(String, String)] = [
        ("plain", "plain"), ("a,b", "\"a,b\""), ("say \"hi\"", "\"say \"\"hi\"\"\""), ("a\nb", "\"a\nb\""),
        ("a\r\nb", "\"a\r\nb\""), ("=1+1", "'=1+1"), ("+44 7700", "'+44 7700"), ("@home", "'@home"),
        ("-note", "'-note"),
    ]

    @Test(arguments: cellCases)
    func csvCellsAreQuotedAndGuarded(value: String, expected: String) {
        #expect(TransactionCSV.cell(TransactionCSV.formulaSafe(value)) == expected)
    }

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
