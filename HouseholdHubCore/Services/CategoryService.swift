import Foundation
import SwiftData
import Synchronization

/// Category lifecycle (spec §7.3, §8.4): system seed, archive instead of delete when referenced, reassignment.
/// One instance per container, like `TransactionService`.
///
/// Known limit: `delete` counts references in this actor's context while `TransactionService.create` validates the
/// category in its own; a transaction created between the two could reference a just-deleted category. The UI
/// never runs both at once, and `ledgerLine()` does not depend on the category existing.
@ModelActor
public actor CategoryService {
    private static let instances = Mutex<[ObjectIdentifier: CategoryService]>([:])

    public static func make(container: ModelContainer) -> CategoryService {
        instances.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let service = CategoryService(modelContainer: container)
            cache[ObjectIdentifier(container)] = service
            return service
        }
    }

    /// Inserts the default system categories once. Names are stored data and can be renamed by the user.
    public func seedSystemCategoriesIfNeeded(now: Date) throws {
        begin()
        let system = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.isSystem == true })
        guard try modelContext.fetchCount(system) == 0 else { return }
        for (index, seed) in SystemCategory.defaults.enumerated() {
            let record = CategoryRecord(
                name: seed.name, icon: seed.icon, color: seed.color, kind: seed.kind, sortOrder: index, isSystem: true,
                now: now)
            modelContext.insert(record)
        }
        try commit()
    }

    @discardableResult
    public func create(name: String, icon: String, color: ColorToken, kind: CategoryKind, now: Date) throws -> UUID {
        begin()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyCategoryName }
        let count = try modelContext.fetchCount(FetchDescriptor<CategoryRecord>())
        let record = CategoryRecord(name: trimmed, icon: icon, color: color, kind: kind, sortOrder: count, now: now)
        modelContext.insert(record)
        try commit()
        return record.id
    }

    /// Edits a category. Changing its kind is refused if existing transactions, series, or wishlist items would no
    /// longer fit.
    public func update(
        category id: UUID, name: String, icon: String, color: ColorToken, kind: CategoryKind, now: Date
    ) throws {
        begin()
        let category = try requireCategory(id)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyCategoryName }
        if kind != category.kind {
            let target: UUID? = id
            let transactions = try modelContext.fetch(
                FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.categoryID == target }))
            let series = try modelContext.fetch(
                FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == target }))
            let wishes = try modelContext.fetchCount(
                FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.categoryID == target }))
            // A budget limits spending, so like a wishlist item it needs a category that allows expenses.
            let budgets = try modelContext.fetchCount(
                FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.categoryID == id }))
            let wishTypes = Array(repeating: TransactionType.expense, count: wishes + budgets)
            let types = transactions.map(\.type) + series.map(\.type) + wishTypes
            if let misfit = types.first(where: { !kind.allows($0) }) {
                throw LedgerError.categoryKindMismatch(kind, misfit)
            }
        }
        category.name = trimmed
        category.icon = icon
        category.color = color
        category.kind = kind
        category.updatedAt = now
        try commit()
    }

    public func setArchived(_ archived: Bool, category id: UUID, now: Date) throws {
        begin()
        let category = try requireCategory(id)
        category.isArchived = archived
        category.updatedAt = now
        try commit()
    }

    /// Hard-deletes only an unreferenced, non-system category; otherwise the caller must archive (spec §8.4).
    public func delete(category id: UUID) throws {
        begin()
        let category = try requireCategory(id)
        guard !category.isSystem else { throw LedgerError.systemCategoryIsPermanent }
        let references = try referenceCount(id)
        guard references == 0 else { throw LedgerError.categoryInUse(referenceCount: references) }
        try deleteBudget(of: id)
        modelContext.delete(category)
        try commit()
    }

    /// Moves every transaction and series from one category to another; returns how many transactions moved.
    @discardableResult
    public func reassign(from source: UUID, to destination: UUID, now: Date) throws -> Int {
        begin()
        let moved = try moveReferences(from: source, to: destination, now: now)
        try commit()
        return moved
    }

    /// "Move items to another category, then delete this one" in a single save (spec §8.4): either both happen or
    /// neither does.
    @discardableResult
    public func reassignAndDelete(from source: UUID, to destination: UUID, now: Date) throws -> Int {
        begin()
        let category = try requireCategory(source)
        guard !category.isSystem else { throw LedgerError.systemCategoryIsPermanent }
        guard source != destination else { throw LedgerError.categoryInUse(referenceCount: try referenceCount(source)) }
        let moved = try moveReferences(from: source, to: destination, now: now)
        try deleteBudget(of: source)
        modelContext.delete(category)
        try commit()
        return moved
    }

    /// Points every reference at `destination` without saving. Validates everything before the first edit.
    private func moveReferences(from source: UUID, to destination: UUID, now: Date) throws -> Int {
        let target = try requireCategory(destination)
        guard !target.isArchived else { throw LedgerError.archivedCategory }
        let sourceID: UUID? = source
        let transactions = try modelContext.fetch(
            FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.categoryID == sourceID }))
        let series = try modelContext.fetch(
            FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == sourceID }))
        let wishes = try modelContext.fetch(
            FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.categoryID == sourceID }))
        let merchants = try modelContext.fetch(
            FetchDescriptor<Merchant>(predicate: #Predicate { $0.defaultCategoryID == sourceID }))
        // Validate everything before mutating: a throw mid-loop would leave unsaved edits in this actor's context.
        // Wishlist items are future expenses, so they need an expense-capable destination.
        let types = transactions.map(\.type) + series.map(\.type) + wishes.map { _ in TransactionType.expense }
        if let mismatch = types.first(where: { !target.kind.allows($0) }) {
            throw LedgerError.categoryKindMismatch(target.kind, mismatch)
        }
        for record in transactions {
            record.categoryID = destination
            record.updatedAt = now
        }
        for item in series {
            item.categoryID = destination
            item.updatedAt = now
        }
        for item in wishes {
            item.categoryID = destination
            item.updatedAt = now
        }
        // A merchant's default category is only a suggestion, so it follows without a kind check.
        for merchant in merchants {
            merchant.defaultCategoryID = destination
            merchant.updatedAt = now
        }
        return transactions.count
    }

    /// Discards edits left pending by an earlier operation that threw before saving, so this write can't persist
    /// them (the same guard as TaskBoardService).
    func begin() {
        if modelContext.hasChanges {
            modelContext.rollback()
        }
    }

    /// Saves, or discards every pending edit if the save fails, so no later save can persist a failed operation.
    func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func requireCategory(_ id: UUID) throws -> CategoryRecord {
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownCategory }
        return category
    }

    private func referenceCount(_ id: UUID) throws -> Int {
        let target: UUID? = id
        let transactions = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.categoryID == target })
        let series = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == target })
        let wishes = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.categoryID == target })
        let merchants = FetchDescriptor<Merchant>(predicate: #Predicate { $0.defaultCategoryID == target })
        return try modelContext.fetchCount(transactions) + modelContext.fetchCount(series)
            + modelContext.fetchCount(wishes) + modelContext.fetchCount(merchants)
    }
}

/// Default categories created on first launch. Colors meet WCAG 3:1 against white for glyph-on-fill use.
public struct SystemCategory: Sendable {
    public let name: String
    public let icon: String
    public let color: ColorToken
    public let kind: CategoryKind

    public static let defaults: [SystemCategory] = [
        SystemCategory(name: "Groceries", icon: "cart", hex: "#2E7D32", kind: .expense),
        SystemCategory(name: "Dining", icon: "fork.knife", hex: "#C62828", kind: .expense),
        SystemCategory(name: "Housing", icon: "house", hex: "#1565C0", kind: .expense),
        SystemCategory(name: "Utilities", icon: "bolt", hex: "#EF6C00", kind: .expense),
        SystemCategory(name: "Transportation", icon: "car", hex: "#6A1B9A", kind: .expense),
        SystemCategory(name: "Health", icon: "cross.case", hex: "#AD1457", kind: .expense),
        SystemCategory(name: "Entertainment", icon: "film", hex: "#00838F", kind: .expense),
        SystemCategory(name: "Shopping", icon: "bag", hex: "#4527A0", kind: .expense),
        SystemCategory(name: "Other", icon: "ellipsis.circle", hex: "#546E7A", kind: .expense),
        SystemCategory(name: "Salary", icon: "briefcase", hex: "#00695C", kind: .income),
        SystemCategory(name: "Other Income", icon: "plus.circle", hex: "#558B2F", kind: .income),
    ]

    private init(name: String, icon: String, hex: String, kind: CategoryKind) {
        self.name = name
        self.icon = icon
        self.color = ColorToken(hex: hex) ?? .black
        self.kind = kind
    }
}
