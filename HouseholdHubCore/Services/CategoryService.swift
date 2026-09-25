import Foundation
import SwiftData

/// Category lifecycle (spec §7.3, §8.4): system seed, archive instead of delete when referenced, reassignment.
@ModelActor
public actor CategoryService {
    public static func make(container: ModelContainer) -> CategoryService {
        CategoryService(modelContainer: container)
    }

    /// Inserts the default system categories once. Names are stored data and can be renamed by the user.
    public func seedSystemCategoriesIfNeeded(now: Date) throws {
        let system = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.isSystem == true })
        guard try modelContext.fetchCount(system) == 0 else { return }
        for (index, seed) in SystemCategory.defaults.enumerated() {
            let record = CategoryRecord(
                name: seed.name, icon: seed.icon, color: seed.color, kind: seed.kind, sortOrder: index, isSystem: true,
                now: now)
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    public func setArchived(_ archived: Bool, category id: UUID, now: Date) throws {
        let category = try requireCategory(id)
        category.isArchived = archived
        category.updatedAt = now
        try modelContext.save()
    }

    /// Hard-deletes only an unreferenced, non-system category; otherwise the caller must archive (spec §8.4).
    public func delete(category id: UUID) throws {
        let category = try requireCategory(id)
        guard !category.isSystem else { throw LedgerError.systemCategoryIsPermanent }
        let references = try referenceCount(id)
        guard references == 0 else { throw LedgerError.categoryInUse(transactionCount: references) }
        modelContext.delete(category)
        try modelContext.save()
    }

    /// Moves every transaction and series from one category to another; returns how many transactions moved.
    @discardableResult
    public func reassign(from source: UUID, to destination: UUID, now: Date) throws -> Int {
        let target = try requireCategory(destination)
        guard !target.isArchived else { throw LedgerError.archivedCategory }
        let sourceID: UUID? = source
        let transactions = try modelContext.fetch(
            FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.categoryID == sourceID }))
        // Validate everything before mutating: a throw mid-loop would leave unsaved edits in this actor's context.
        if let mismatch = transactions.first(where: { !target.kind.allows($0.type) }) {
            throw LedgerError.categoryKindMismatch(target.kind, mismatch.type)
        }
        for record in transactions {
            record.categoryID = destination
            record.updatedAt = now
        }
        let series = try modelContext.fetch(
            FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == sourceID }))
        for item in series {
            item.categoryID = destination
            item.updatedAt = now
        }
        try modelContext.save()
        return transactions.count
    }

    private func requireCategory(_ id: UUID) throws -> CategoryRecord {
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownCategory }
        return category
    }

    private func referenceCount(_ id: UUID) throws -> Int {
        let target: UUID? = id
        let transactions = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.categoryID == target })
        let series = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.categoryID == target })
        return try modelContext.fetchCount(transactions) + modelContext.fetchCount(series)
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
