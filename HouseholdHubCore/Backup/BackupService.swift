import Foundation
import SwiftData
import Synchronization

/// Whole-store backup and restore (spec §26). Export reads one consistent snapshot; restore validates the entire
/// backup first and then replaces the store in a single save, so a bad file changes nothing (§26.1).
///
/// Known limit: the other service actors keep their own contexts. They fetch from the store on every operation, so
/// they see restored data, but the UI should not run another write while a restore is in progress.
@ModelActor
public actor BackupService {
    private static let instances = Mutex<[ObjectIdentifier: BackupService]>([:])

    public static func make(container: ModelContainer) -> BackupService {
        instances.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let service = BackupService(modelContainer: container)
            cache[ObjectIdentifier(container)] = service
            return service
        }
    }

    public struct RestoreSummary: Equatable, Sendable {
        public let transactions: Int
        public let wishlistItems: Int
        public let tasks: Int
        /// Image references dropped because the file was not in the backup (Sprint 6 default 4).
        public let missingMedia: Int
    }

    // MARK: Export

    /// A snapshot of every record. `mediaSizes` gives each image file's size, or nil when the file is missing (then
    /// it is left out of the manifest).
    public func snapshot(
        now: Date, appVersion: String, mediaSizes: @Sendable (String) -> Int?
    ) throws -> BackupDTO {
        var settingsDescriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        guard let settings = try modelContext.fetch(settingsDescriptor).first else { throw LedgerError.settingsMissing }
        let wishes = try modelContext.fetch(FetchDescriptor<WishlistItem>())
        let manifest = wishes.compactMap(\.mediaReference).sorted().compactMap { reference in
            mediaSizes(reference).map { BackupDTO.MediaEntry(reference: reference, sizeBytes: $0) }
        }
        return BackupDTO(
            schemaVersion: BackupDTO.currentSchemaVersion, exportedAt: now, appVersion: appVersion,
            settings: BackupDTO.Settings(
                id: settings.id, currencyCode: settings.currencyCode, onboardingCompleted: settings.onboardingCompleted,
                startingBalanceMinorUnits: settings.startingBalanceMinorUnits,
                startingBalanceDate: settings.startingBalanceDate,
                includePendingInProjection: settings.includePendingInProjection,
                defaultAnalyticsPeriod: settings.defaultAnalyticsPeriodRawValue, createdAt: settings.createdAt,
                updatedAt: settings.updatedAt),
            categories: sorted(try fetch(CategoryRecord.self).map(Self.dto), by: \.id),
            merchants: sorted(try fetch(Merchant.self).map(Self.dto), by: \.id),
            transactions: sorted(try fetch(TransactionRecord.self).map(Self.dto), by: \.id),
            recurringTransactions: sorted(try fetch(RecurringTransaction.self).map { try Self.dto($0) }, by: \.id),
            wishlistItems: sorted(wishes.map(Self.dto), by: \.id),
            boardColumns: sorted(try fetch(BoardColumn.self).map(Self.dto), by: \.id),
            taskItems: sorted(try fetch(TaskItem.self).map(Self.dto), by: \.id),
            subtaskItems: sorted(try fetch(SubtaskItem.self).map(Self.dto), by: \.id),
            mediaManifest: manifest)
    }

    // MARK: Restore

    /// Replaces the whole store with `backup` in one save, after `BackupValidator` accepts all of it. Images whose
    /// files are not in `availableMedia` are dropped from their items and counted.
    public func restore(_ backup: BackupDTO, availableMedia: Set<String>, now: Date) throws -> RestoreSummary {
        try BackupValidator.validate(backup)
        if modelContext.hasChanges {
            modelContext.rollback()
        }
        do {
            try deleteAll()
            let settings = AppSettings(id: backup.settings.id, currencyCode: backup.settings.currencyCode, now: now)
            settings.onboardingCompleted = backup.settings.onboardingCompleted
            settings.startingBalanceMinorUnits = backup.settings.startingBalanceMinorUnits
            settings.startingBalanceDate = backup.settings.startingBalanceDate
            settings.includePendingInProjection = backup.settings.includePendingInProjection
            settings.defaultAnalyticsPeriodRawValue = backup.settings.defaultAnalyticsPeriod
            settings.createdAt = backup.settings.createdAt
            settings.updatedAt = backup.settings.updatedAt
            modelContext.insert(settings)
            backup.categories.forEach { modelContext.insert(Self.model($0)) }
            backup.merchants.forEach { modelContext.insert(Self.model($0)) }
            backup.transactions.forEach { modelContext.insert(Self.model($0)) }
            for item in backup.recurringTransactions {
                modelContext.insert(try Self.model(item))
            }
            var missing = 0
            for wish in backup.wishlistItems {
                let item = Self.model(wish)
                if let reference = item.mediaReference, !availableMedia.contains(reference) {
                    item.mediaReference = nil
                    missing += 1
                }
                modelContext.insert(item)
            }
            backup.boardColumns.forEach { modelContext.insert(Self.model($0)) }
            backup.taskItems.forEach { modelContext.insert(Self.model($0)) }
            backup.subtaskItems.forEach { modelContext.insert(Self.model($0)) }
            try modelContext.save()
            return RestoreSummary(
                transactions: backup.transactions.count, wishlistItems: backup.wishlistItems.count,
                tasks: backup.taskItems.count, missingMedia: missing)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteAll() throws {
        try fetch(AppSettings.self).forEach(modelContext.delete)
        try fetch(CategoryRecord.self).forEach(modelContext.delete)
        try fetch(Merchant.self).forEach(modelContext.delete)
        try fetch(TransactionRecord.self).forEach(modelContext.delete)
        try fetch(RecurringTransaction.self).forEach(modelContext.delete)
        try fetch(WishlistItem.self).forEach(modelContext.delete)
        try fetch(BoardColumn.self).forEach(modelContext.delete)
        try fetch(TaskItem.self).forEach(modelContext.delete)
        try fetch(SubtaskItem.self).forEach(modelContext.delete)
    }

    /// Stable order, so two backups of the same data are byte-for-byte identical apart from `exportedAt`.
    private func sorted<T>(_ values: [T], by id: KeyPath<T, UUID>) -> [T] {
        values.sorted { $0[keyPath: id].uuidString < $1[keyPath: id].uuidString }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }
}

// MARK: Mapping

extension BackupService {
    static func dto(_ model: CategoryRecord) -> BackupDTO.Category {
        BackupDTO.Category(
            id: model.id, name: model.name, icon: model.icon, color: model.color, kind: model.kindRawValue,
            sortOrder: model.sortOrder, isSystem: model.isSystem, isArchived: model.isArchived,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Category) -> CategoryRecord {
        let kind = CategoryKind(rawValue: dto.kind) ?? .both
        let model = CategoryRecord(
            id: dto.id, name: dto.name, icon: dto.icon, color: dto.color, kind: kind, sortOrder: dto.sortOrder,
            isSystem: dto.isSystem, now: dto.createdAt)
        model.isArchived = dto.isArchived
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: Merchant) -> BackupDTO.MerchantDTO {
        BackupDTO.MerchantDTO(
            id: model.id, displayName: model.displayName, defaultCategoryID: model.defaultCategoryID,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.MerchantDTO) -> Merchant {
        let model = Merchant(id: dto.id, displayName: dto.displayName, now: dto.createdAt)
        model.defaultCategoryID = dto.defaultCategoryID
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: TransactionRecord) -> BackupDTO.Transaction {
        BackupDTO.Transaction(
            id: model.id, amountMinorUnits: model.amountMinorUnits, currencyCode: model.currencyCode,
            type: model.typeRawValue, status: model.statusRawValue, source: model.sourceRawValue,
            occurredAt: model.occurredAt, merchantID: model.merchantID,
            merchantNameSnapshot: model.merchantNameSnapshot, categoryID: model.categoryID, notes: model.notes,
            recurringSeriesID: model.recurringSeriesID,
            scheduledOccurrence: model.scheduledOccurrence, wishlistItemID: model.wishlistItemID,
            isAIClassified: model.isAIClassified, createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Transaction) -> TransactionRecord {
        // Raw values were validated; the stored strings are copied as they are.
        let amount = Money(minorUnits: dto.amountMinorUnits, currencyCode: dto.currencyCode)
        let model = TransactionRecord(
            id: dto.id, amount: amount, type: .expense, status: .posted, source: .manual, occurredAt: dto.occurredAt,
            now: dto.createdAt)
        model.typeRawValue = dto.type
        model.statusRawValue = dto.status
        model.sourceRawValue = dto.source
        model.merchantID = dto.merchantID
        model.merchantNameSnapshot = dto.merchantNameSnapshot
        model.categoryID = dto.categoryID
        model.notes = dto.notes
        model.recurringSeriesID = dto.recurringSeriesID
        model.scheduledOccurrence = dto.scheduledOccurrence
        model.wishlistItemID = dto.wishlistItemID
        model.isAIClassified = dto.isAIClassified
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: RecurringTransaction) throws -> BackupDTO.Recurring {
        BackupDTO.Recurring(
            id: model.id, templateAmountMinorUnits: model.templateAmountMinorUnits, currencyCode: model.currencyCode,
            type: model.typeRawValue, categoryID: model.categoryID, merchantID: model.merchantID, notes: model.notes,
            rule: try model.rule(), timeZoneIdentifier: model.timeZoneIdentifier, startDate: model.startDate,
            endDate: model.endDate, nextOccurrence: model.nextOccurrence, isEnabled: model.isEnabled,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Recurring) throws -> RecurringTransaction {
        let zone = TimeZone(identifier: dto.timeZoneIdentifier) ?? .gmt
        let model = try RecurringTransaction(
            id: dto.id, templateAmount: Money(minorUnits: dto.templateAmountMinorUnits, currencyCode: dto.currencyCode),
            type: TransactionType(rawValue: dto.type) ?? .expense, rule: dto.rule, timeZone: zone,
            startDate: dto.startDate, endDate: dto.endDate, now: dto.createdAt)
        model.typeRawValue = dto.type
        model.timeZoneIdentifier = dto.timeZoneIdentifier
        model.categoryID = dto.categoryID
        model.merchantID = dto.merchantID
        model.notes = dto.notes
        model.nextOccurrence = dto.nextOccurrence
        model.isEnabled = dto.isEnabled
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: WishlistItem) -> BackupDTO.Wish {
        BackupDTO.Wish(
            id: model.id, name: model.name, estimatedPriceMinorUnits: model.estimatedPriceMinorUnits,
            actualPriceMinorUnits: model.actualPriceMinorUnits, currencyCode: model.currencyCode,
            priority: model.priorityRawValue, status: model.statusRawValue, categoryID: model.categoryID,
            notes: model.notes, mediaReference: model.mediaReference, linkedTaskID: model.linkedTaskID,
            purchasedTransactionID: model.purchasedTransactionID, targetDate: model.targetDate,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Wish) -> WishlistItem {
        let model = WishlistItem(
            id: dto.id, name: dto.name,
            estimatedPrice: Money(minorUnits: dto.estimatedPriceMinorUnits, currencyCode: dto.currencyCode),
            priority: .medium, now: dto.createdAt)
        model.priorityRawValue = dto.priority
        model.statusRawValue = dto.status
        model.actualPriceMinorUnits = dto.actualPriceMinorUnits
        model.categoryID = dto.categoryID
        model.notes = dto.notes
        model.mediaReference = dto.mediaReference
        model.linkedTaskID = dto.linkedTaskID
        model.purchasedTransactionID = dto.purchasedTransactionID
        model.targetDate = dto.targetDate
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: BoardColumn) -> BackupDTO.Column {
        BackupDTO.Column(
            id: model.id, name: model.name, sortOrder: model.sortOrder, isSystem: model.isSystem,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Column) -> BoardColumn {
        let model = BoardColumn(
            id: dto.id, name: dto.name, sortOrder: dto.sortOrder, isSystem: dto.isSystem, now: dto.createdAt)
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: TaskItem) -> BackupDTO.TaskDTO {
        BackupDTO.TaskDTO(
            id: model.id, title: model.title, notes: model.notes, columnID: model.columnID,
            priority: model.priorityRawValue, dueDate: model.dueDate, completedAt: model.completedAt,
            sortOrder: model.sortOrder, linkedWishlistItemID: model.linkedWishlistItemID,
            linkedTransactionID: model.linkedTransactionID, archivedAt: model.archivedAt, createdAt: model.createdAt,
            updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.TaskDTO) -> TaskItem {
        let model = TaskItem(
            id: dto.id, title: dto.title, columnID: dto.columnID, priority: .medium, sortOrder: dto.sortOrder,
            now: dto.createdAt)
        model.priorityRawValue = dto.priority
        model.notes = dto.notes
        model.dueDate = dto.dueDate
        model.completedAt = dto.completedAt
        model.linkedWishlistItemID = dto.linkedWishlistItemID
        model.linkedTransactionID = dto.linkedTransactionID
        model.archivedAt = dto.archivedAt
        model.updatedAt = dto.updatedAt
        return model
    }

    static func dto(_ model: SubtaskItem) -> BackupDTO.Subtask {
        BackupDTO.Subtask(
            id: model.id, title: model.title, isCompleted: model.isCompleted, sortOrder: model.sortOrder,
            taskID: model.taskID, createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func model(_ dto: BackupDTO.Subtask) -> SubtaskItem {
        let model = SubtaskItem(
            id: dto.id, title: dto.title, taskID: dto.taskID, sortOrder: dto.sortOrder, now: dto.createdAt)
        model.isCompleted = dto.isCompleted
        model.updatedAt = dto.updatedAt
        return model
    }
}
