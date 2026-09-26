import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Tests the Sprint 9 data-safety review asked for: the Face ID setting across backups, merchant default
/// categories, the move-and-delete guards, link repair on export, and the backup file's key names.
struct Sprint9Tests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Stack {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let board: TaskBoardService
        let backup: BackupService

        func context() -> ModelContext { ModelContext(container) }

        func settings() throws -> AppSettings {
            try #require(try context().fetch(FetchDescriptor<AppSettings>()).first)
        }
    }

    private func makeStack() async throws -> Stack {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let stack = Stack(
            container: container, ledger: .make(container: container), categories: .make(container: container),
            board: .make(container: container), backup: .make(container: container))
        try await stack.ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await stack.categories.seedSystemCategoriesIfNeeded(now: now)
        try await stack.board.seedDefaultColumnsIfNeeded(now: now)
        return stack
    }

    private func snapshot(_ stack: Stack) async throws -> BackupDTO {
        try await stack.backup.snapshot(now: now, appVersion: "1") { _ in nil }
    }

    private func category(_ name: String, in stack: Stack) throws -> UUID {
        try #require(try stack.context().fetch(FetchDescriptor<CategoryRecord>()).first { $0.name == name }).id
    }

    // MARK: Face ID is device configuration (§26.1)

    @Test func theLockSettingIsNeverInABackupFile() async throws {
        let stack = try await makeStack()
        try await stack.ledger.setFaceIDEnabled(true, now: now)
        #expect(try stack.settings().faceIDEnabled)
        let data = try BackupDTO.encoder().encode(try await snapshot(stack))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.lowercased().contains("faceid"))
    }

    @Test func restoringKeepsThisDevicesLockWhateverTheBackupsSettingsID() async throws {
        let other = try await makeStack()
        let foreign = try await snapshot(other)

        let device = try await makeStack()
        try await device.ledger.setFaceIDEnabled(true, now: now)
        let own = try await snapshot(device)
        _ = try await device.backup.restore(own, availableMedia: [], now: now)
        #expect(try device.settings().faceIDEnabled, "Same settings id: the lock stays on")
        _ = try await device.backup.restore(foreign, availableMedia: [], now: now)
        #expect(try device.settings().faceIDEnabled, "Another device's backup must not turn the lock off")

        let fresh = HouseholdContainerFactory()
        let container = try fresh.makeContainer(configuration: .inMemory)
        _ = try await BackupService.make(container: container).restore(own, availableMedia: [], now: now)
        let restored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        #expect(!restored.faceIDEnabled, "A fresh install starts unlocked")
    }

    @Test func theWidgetHidesAmountsWhileTheLockIsOn() async throws {
        let stack = try await makeStack()
        let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
        #expect(try await !stack.ledger.widgetSnapshot(now: now, calendar: calendar).amountsHidden)
        try await stack.ledger.setFaceIDEnabled(true, now: now)
        #expect(try await stack.ledger.widgetSnapshot(now: now, calendar: calendar).amountsHidden)
    }

    // MARK: Merchant default categories count as references

    @Test func aMerchantDefaultBlocksDeletionAndFollowsAMove() async throws {
        let stack = try await makeStack()
        let custom = CategoryRecord(
            name: "Coffee", icon: "cup.and.saucer", color: .black, kind: .expense, sortOrder: 99, now: now)
        let merchant = Merchant(displayName: "Café Luna", now: now)
        merchant.defaultCategoryID = custom.id
        let context = stack.context()
        context.insert(custom)
        context.insert(merchant)
        try context.save()
        let coffee = custom.id
        let groceries = try category("Groceries", in: stack)
        let categories = stack.categories

        await #expect(throws: LedgerError.categoryInUse(referenceCount: 1)) {
            try await categories.delete(category: coffee)
        }
        #expect(try await categories.reassignAndDelete(from: coffee, to: groceries, now: now) == 0)
        let merchants = try stack.context().fetch(FetchDescriptor<Merchant>())
        #expect(merchants.map(\.defaultCategoryID) == [groceries])
    }

    @Test func moveAndDeleteRefusesSystemSameAndArchivedTargets() async throws {
        let stack = try await makeStack()
        let dining = try category("Dining", in: stack)
        let groceries = try category("Groceries", in: stack)
        let custom = CategoryRecord(
            name: "Coffee", icon: "cup.and.saucer", color: .black, kind: .expense, sortOrder: 99, now: now)
        let context = stack.context()
        context.insert(custom)
        try context.save()
        let coffee = custom.id
        let categories = stack.categories

        await #expect(throws: LedgerError.systemCategoryIsPermanent) {
            try await categories.reassignAndDelete(from: dining, to: groceries, now: now)
        }
        await #expect(throws: LedgerError.categoryInUse(referenceCount: 0)) {
            try await categories.reassignAndDelete(from: coffee, to: coffee, now: now)
        }
        try await categories.setArchived(true, category: groceries, now: now)
        await #expect(throws: LedgerError.archivedCategory) {
            try await categories.reassignAndDelete(from: coffee, to: groceries, now: now)
        }
        let stillThere = try stack.context().fetch(FetchDescriptor<CategoryRecord>()).contains { $0.id == coffee }
        #expect(stillThere)
    }

    // MARK: Links

    @Test func changingATasksWishlistLinkClearsTheOldItemsBackLink() async throws {
        let stack = try await makeStack()
        let price = Money(minorUnits: 4_000, currencyCode: "CAD")
        let ledger = stack.ledger
        let lamp = try await ledger.createWishlistItem(WishlistDraft(name: "Lamp", estimatedPrice: price), now: now)
        let rug = try await ledger.createWishlistItem(WishlistDraft(name: "Rug", estimatedPrice: price), now: now)
        let task = try await stack.board.createTask(TaskDraft(title: "Buy", linkedWishlistItemID: lamp), now: now)
        // Restored data can carry the reverse link; the services never set it themselves.
        let context = stack.context()
        let lampRecord = try #require(try context.fetch(FetchDescriptor<WishlistItem>()).first { $0.id == lamp })
        lampRecord.linkedTaskID = task
        try context.save()

        try await stack.board.updateTask(task, with: TaskDraft(title: "Buy", linkedWishlistItemID: rug), now: now)
        let backup = try await snapshot(stack)
        try BackupValidator.validate(backup)
        let anyBackLink = backup.wishlistItems.contains { $0.linkedTaskID != nil }
        #expect(!anyBackLink)
    }

    @Test func exportDropsOptionalLinksThatPointAtNothing() async throws {
        let stack = try await makeStack()
        let task = try await stack.board.createTask(TaskDraft(title: "Orphan"), now: now)
        var backup = try await snapshot(stack)
        let index = try #require(backup.taskItems.firstIndex { $0.id == task })
        backup.taskItems[index].linkedTransactionID = UUID()
        backup.taskItems[index].linkedWishlistItemID = UUID()
        #expect(throws: (any Error).self) { try BackupValidator.validate(backup) }
        let dropped = backup.droppingDanglingLinks()
        #expect(dropped == 2)
        try BackupValidator.validate(backup)
    }

    // MARK: File format

    /// Renaming one of these Swift properties would silently change the backup format; this pins the key names.
    @Test func backupFilesUseTheDocumentedKeyNames() async throws {
        let stack = try await makeStack()
        try await stack.ledger.setAppearance(theme: .dark, accent: ColorToken(hex: "#6A1B9A"), now: now)
        let spent = try await stack.ledger.create(
            TransactionDraft(amount: Money(minorUnits: 500, currencyCode: "CAD"), type: .expense, occurredAt: now),
            now: now)
        _ = try await stack.board.createTask(TaskDraft(title: "Receipt", linkedTransactionID: spent), now: now)
        let data = try BackupDTO.encoder().encode(try await snapshot(stack))
        let text = try #require(String(data: data, encoding: .utf8))
        let keys = [
            "selectedTheme", "accentColorHex", "defaultQuickAddType", "widgetShowsBalance", "linkedTransactionID",
        ]
        for key in keys {
            #expect(text.contains("\"\(key)\""), "Missing key \(key)")
        }
    }

    @Test func restoredPreferencesAreNormalized() async throws {
        let stack = try await makeStack()
        var backup = try await snapshot(stack)
        backup.settings.accentColorHex = "not a color"
        backup.settings.selectedTheme = "sepia"
        _ = try await stack.backup.restore(backup, availableMedia: [], now: now)
        let settings = try stack.settings()
        #expect(settings.accentColorHex.isEmpty && settings.selectedThemeRawValue == "system")
    }
}
