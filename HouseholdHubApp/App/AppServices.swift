import HouseholdHubCore
import SwiftData
import SwiftUI

/// The write-side services, one instance per container. Views read with `@Query`; every write goes through here.
struct AppServices: Sendable {
    let transactions: TransactionService
    let categories: CategoryService

    init(container: ModelContainer) {
        transactions = .make(container: container)
        categories = .make(container: container)
    }
}

extension EnvironmentValues {
    @Entry var services: AppServices? = nil
}
