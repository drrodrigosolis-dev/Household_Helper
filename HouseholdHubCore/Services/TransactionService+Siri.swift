import Foundation
import SwiftData

/// What the Siri intents need to read before they draft (Sprint 25), in one call so the values agree.
public struct SiriContext: Equatable, Sendable {
    public let settings: SettingsSnapshot?
    /// Intelligence ▸ "Quick Add understanding": the on-device model may read the sentence.
    public let understandsText: Bool
    /// Intelligence ▸ "Category suggestions": the on-device model may pick a category.
    public let suggestsCategories: Bool
    /// Active categories, in the app's order.
    public let categories: [QuickAddCategoryOption]

    public init(
        settings: SettingsSnapshot?, understandsText: Bool, suggestsCategories: Bool,
        categories: [QuickAddCategoryOption]
    ) {
        self.settings = settings
        self.understandsText = understandsText
        self.suggestsCategories = suggestsCategories
        self.categories = categories
    }
}

extension TransactionService {
    /// Read-only: the settings, the two AI switches the Siri intents honour, and the active categories.
    public func siriContext() throws -> SiriContext {
        var descriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        let stored = try modelContext.fetch(descriptor).first
        let records = try modelContext.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { !$0.isArchived }
        return SiriContext(
            settings: try settingsSnapshot(), understandsText: stored?.naturalLanguageEnabled ?? false,
            suggestsCategories: stored?.aiCategorizationEnabled ?? false,
            categories: records.map { QuickAddCategoryOption(id: $0.id, name: $0.name, kind: $0.kind) })
    }
}
