import HouseholdHubCore
import SwiftData
import SwiftUI

/// The write-side services, one instance per container. Views read with `@Query`; every write goes through here.
struct AppServices: Sendable {
    let transactions: TransactionService
    let categories: CategoryService
    let board: TaskBoardService
    let analytics: AnalyticsService
    let backup: BackupService
    /// Media files outside the store (spec §5.5); nil only if Application Support is unavailable.
    let images: ImageStore?

    init(container: ModelContainer) {
        transactions = .make(container: container)
        categories = .make(container: container)
        board = .make(container: container)
        analytics = .make(container: container)
        backup = .make(container: container)
        images = try? ImageStore.standard()
    }
}

extension EnvironmentValues {
    @Entry var services: AppServices? = nil
}
