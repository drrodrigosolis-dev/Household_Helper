import HouseholdHubCore
import SwiftData
import SwiftUI

@main
struct HouseholdHubApp: App {
    private struct LoadedStore {
        let container: ModelContainer
        let services: AppServices
    }

    private let store: Result<LoadedStore, any Error>

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
        let configuration = PersistenceConfiguration(useInMemoryStore: inMemory)
        store = Result {
            let container = try HouseholdContainerFactory().makeContainer(configuration: configuration)
            return LoadedStore(container: container, services: AppServices(container: container))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let loaded):
                AppRootView()
                    .environment(\.services, loaded.services)
                    .modelContainer(loaded.container)
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}
