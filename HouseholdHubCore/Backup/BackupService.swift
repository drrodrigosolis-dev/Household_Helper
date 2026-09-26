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

    /// The photo references the store uses now.
    public func mediaReferences() throws -> Set<String> {
        Set(try fetch(WishlistItem.self).compactMap(\.mediaReference))
    }

    // MARK: Restore

    /// Replaces the whole store with `backup` in one save, after `BackupValidator` accepts all of it. Images whose
    /// files are not in `availableMedia` are dropped from their items and counted.
    ///
    /// Records are merged by id rather than deleted and re-inserted: a record in both the store and the backup is
    /// updated in place, one only in the backup is inserted, one only in the store is deleted. Restoring a device's
    /// own backup (same ids) therefore never relies on how SwiftData resolves a unique-id clash within one save, and
    /// a screen still showing a record keeps a live object.
    public func restore(_ backup: BackupDTO, availableMedia: Set<String>, now: Date) throws -> RestoreSummary {
        try BackupValidator.validate(backup)
        if modelContext.hasChanges {
            modelContext.rollback()
        }
        do {
            try merge([backup.settings], id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.categories, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.merchants, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.transactions, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.recurringTransactions, id: \.id, make: Self.make, apply: Self.apply)
            let wishes = backup.wishlistItems.map { wish in
                var copy = wish
                if let reference = copy.mediaReference, !availableMedia.contains(reference) {
                    copy.mediaReference = nil
                }
                return copy
            }
            try merge(wishes, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.boardColumns, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.taskItems, id: \.id, make: Self.make, apply: Self.apply)
            try merge(backup.subtaskItems, id: \.id, make: Self.make, apply: Self.apply)
            try modelContext.save()
            let missing = zip(backup.wishlistItems, wishes).filter { $0.mediaReference != $1.mediaReference }.count
            return RestoreSummary(
                transactions: backup.transactions.count, wishlistItems: backup.wishlistItems.count,
                tasks: backup.taskItems.count, missingMedia: missing)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Updates, inserts, and deletes one model type so the store holds exactly `dtos`.
    private func merge<Model: PersistentModel & Identified, DTO>(
        _ dtos: [DTO], id: KeyPath<DTO, UUID>, make: (DTO) throws -> Model, apply: (DTO, Model) throws -> Void
    ) throws {
        var existing = Dictionary(
            try fetch(Model.self).map { ($0.recordID, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            if let model = existing.removeValue(forKey: dto[keyPath: id]) {
                try apply(dto, model)
            } else {
                modelContext.insert(try make(dto))
            }
        }
        for model in existing.values {
            modelContext.delete(model)
        }
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

/// A model's stored id, so `merge` can match backup records to existing ones.
protocol Identified {
    var recordID: UUID { get }
}

extension AppSettings: Identified { var recordID: UUID { id } }
extension CategoryRecord: Identified { var recordID: UUID { id } }
extension Merchant: Identified { var recordID: UUID { id } }
extension TransactionRecord: Identified { var recordID: UUID { id } }
extension RecurringTransaction: Identified { var recordID: UUID { id } }
extension WishlistItem: Identified { var recordID: UUID { id } }
extension BoardColumn: Identified { var recordID: UUID { id } }
extension TaskItem: Identified { var recordID: UUID { id } }
extension SubtaskItem: Identified { var recordID: UUID { id } }

/// Each type has `dto` (export), `make` (a new model), and `apply` (copy every stored field onto a model). `make`
/// builds a minimal model and calls `apply`, so a new and an updated record end up identical.
extension BackupService {
    static func make(_ dto: BackupDTO.Settings) -> AppSettings {
        let model = AppSettings(id: dto.id, currencyCode: dto.currencyCode, now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Settings, to model: AppSettings) {
        model.currencyCode = dto.currencyCode
        model.onboardingCompleted = dto.onboardingCompleted
        model.startingBalanceMinorUnits = dto.startingBalanceMinorUnits
        model.startingBalanceDate = dto.startingBalanceDate
        model.includePendingInProjection = dto.includePendingInProjection
        model.defaultAnalyticsPeriodRawValue = dto.defaultAnalyticsPeriod
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: CategoryRecord) -> BackupDTO.Category {
        BackupDTO.Category(
            id: model.id, name: model.name, icon: model.icon, color: model.color, kind: model.kindRawValue,
            sortOrder: model.sortOrder, isSystem: model.isSystem, isArchived: model.isArchived,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.Category) -> CategoryRecord {
        let model = CategoryRecord(
            id: dto.id, name: dto.name, icon: dto.icon, color: dto.color, kind: .both, sortOrder: dto.sortOrder,
            now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Category, to model: CategoryRecord) {
        model.name = dto.name
        model.icon = dto.icon
        model.color = dto.color
        model.kindRawValue = dto.kind
        model.sortOrder = dto.sortOrder
        model.isSystem = dto.isSystem
        model.isArchived = dto.isArchived
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: Merchant) -> BackupDTO.MerchantDTO {
        BackupDTO.MerchantDTO(
            id: model.id, displayName: model.displayName, defaultCategoryID: model.defaultCategoryID,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.MerchantDTO) -> Merchant {
        let model = Merchant(id: dto.id, displayName: dto.displayName, now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.MerchantDTO, to model: Merchant) {
        model.displayName = dto.displayName
        model.normalizedName = Merchant.normalize(dto.displayName)
        model.defaultCategoryID = dto.defaultCategoryID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: TransactionRecord) -> BackupDTO.Transaction {
        BackupDTO.Transaction(
            id: model.id, amountMinorUnits: model.amountMinorUnits, currencyCode: model.currencyCode,
            type: model.typeRawValue, status: model.statusRawValue, source: model.sourceRawValue,
            occurredAt: model.occurredAt, merchantID: model.merchantID,
            merchantNameSnapshot: model.merchantNameSnapshot, categoryID: model.categoryID, notes: model.notes,
            recurringSeriesID: model.recurringSeriesID, scheduledOccurrence: model.scheduledOccurrence,
            wishlistItemID: model.wishlistItemID, isAIClassified: model.isAIClassified, createdAt: model.createdAt,
            updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.Transaction) -> TransactionRecord {
        let amount = Money(minorUnits: dto.amountMinorUnits, currencyCode: dto.currencyCode)
        let model = TransactionRecord(
            id: dto.id, amount: amount, type: .expense, status: .posted, source: .manual, occurredAt: dto.occurredAt,
            now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    /// Raw values were validated; the stored strings are copied as they are.
    static func apply(_ dto: BackupDTO.Transaction, to model: TransactionRecord) {
        model.amountMinorUnits = dto.amountMinorUnits
        model.currencyCode = dto.currencyCode
        model.typeRawValue = dto.type
        model.statusRawValue = dto.status
        model.sourceRawValue = dto.source
        model.occurredAt = dto.occurredAt
        model.merchantID = dto.merchantID
        model.merchantNameSnapshot = dto.merchantNameSnapshot
        model.categoryID = dto.categoryID
        model.notes = dto.notes
        model.recurringSeriesID = dto.recurringSeriesID
        model.scheduledOccurrence = dto.scheduledOccurrence
        model.wishlistItemID = dto.wishlistItemID
        model.isAIClassified = dto.isAIClassified
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: RecurringTransaction) throws -> BackupDTO.Recurring {
        BackupDTO.Recurring(
            id: model.id, templateAmountMinorUnits: model.templateAmountMinorUnits, currencyCode: model.currencyCode,
            type: model.typeRawValue, categoryID: model.categoryID, merchantID: model.merchantID, notes: model.notes,
            rule: try model.rule(), timeZoneIdentifier: model.timeZoneIdentifier, startDate: model.startDate,
            endDate: model.endDate, nextOccurrence: model.nextOccurrence, isEnabled: model.isEnabled,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.Recurring) throws -> RecurringTransaction {
        let amount = Money(minorUnits: dto.templateAmountMinorUnits, currencyCode: dto.currencyCode)
        let model = try RecurringTransaction(
            id: dto.id, templateAmount: amount, type: .expense, rule: dto.rule, timeZone: .gmt,
            startDate: dto.startDate, now: dto.createdAt)
        try apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Recurring, to model: RecurringTransaction) throws {
        model.templateAmountMinorUnits = dto.templateAmountMinorUnits
        model.currencyCode = dto.currencyCode
        model.typeRawValue = dto.type
        model.categoryID = dto.categoryID
        model.merchantID = dto.merchantID
        model.notes = dto.notes
        try model.setRule(dto.rule)
        model.timeZoneIdentifier = dto.timeZoneIdentifier
        model.startDate = dto.startDate
        model.endDate = dto.endDate
        model.nextOccurrence = dto.nextOccurrence
        model.isEnabled = dto.isEnabled
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
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

    static func make(_ dto: BackupDTO.Wish) -> WishlistItem {
        let estimate = Money(minorUnits: dto.estimatedPriceMinorUnits, currencyCode: dto.currencyCode)
        let model = WishlistItem(
            id: dto.id, name: dto.name, estimatedPrice: estimate, priority: .medium, now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Wish, to model: WishlistItem) {
        model.name = dto.name
        model.estimatedPriceMinorUnits = dto.estimatedPriceMinorUnits
        model.actualPriceMinorUnits = dto.actualPriceMinorUnits
        model.currencyCode = dto.currencyCode
        model.priorityRawValue = dto.priority
        model.statusRawValue = dto.status
        model.categoryID = dto.categoryID
        model.notes = dto.notes
        model.mediaReference = dto.mediaReference
        model.linkedTaskID = dto.linkedTaskID
        model.purchasedTransactionID = dto.purchasedTransactionID
        model.targetDate = dto.targetDate
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: BoardColumn) -> BackupDTO.Column {
        BackupDTO.Column(
            id: model.id, name: model.name, sortOrder: model.sortOrder, isSystem: model.isSystem,
            createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.Column) -> BoardColumn {
        let model = BoardColumn(id: dto.id, name: dto.name, sortOrder: dto.sortOrder, now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Column, to model: BoardColumn) {
        model.name = dto.name
        model.sortOrder = dto.sortOrder
        model.isSystem = dto.isSystem
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: TaskItem) -> BackupDTO.TaskDTO {
        BackupDTO.TaskDTO(
            id: model.id, title: model.title, notes: model.notes, columnID: model.columnID,
            priority: model.priorityRawValue, dueDate: model.dueDate, completedAt: model.completedAt,
            sortOrder: model.sortOrder, linkedWishlistItemID: model.linkedWishlistItemID,
            linkedTransactionID: model.linkedTransactionID, archivedAt: model.archivedAt, createdAt: model.createdAt,
            updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.TaskDTO) -> TaskItem {
        let model = TaskItem(
            id: dto.id, title: dto.title, columnID: dto.columnID, priority: .medium, sortOrder: dto.sortOrder,
            now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.TaskDTO, to model: TaskItem) {
        model.title = dto.title
        model.notes = dto.notes
        model.columnID = dto.columnID
        model.priorityRawValue = dto.priority
        model.dueDate = dto.dueDate
        model.completedAt = dto.completedAt
        model.sortOrder = dto.sortOrder
        model.linkedWishlistItemID = dto.linkedWishlistItemID
        model.linkedTransactionID = dto.linkedTransactionID
        model.archivedAt = dto.archivedAt
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func dto(_ model: SubtaskItem) -> BackupDTO.Subtask {
        BackupDTO.Subtask(
            id: model.id, title: model.title, isCompleted: model.isCompleted, sortOrder: model.sortOrder,
            taskID: model.taskID, createdAt: model.createdAt, updatedAt: model.updatedAt)
    }

    static func make(_ dto: BackupDTO.Subtask) -> SubtaskItem {
        let model = SubtaskItem(
            id: dto.id, title: dto.title, taskID: dto.taskID, sortOrder: dto.sortOrder, now: dto.createdAt)
        apply(dto, to: model)
        return model
    }

    static func apply(_ dto: BackupDTO.Subtask, to model: SubtaskItem) {
        model.title = dto.title
        model.isCompleted = dto.isCompleted
        model.sortOrder = dto.sortOrder
        model.taskID = dto.taskID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }
}
