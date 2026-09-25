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
    private let forcedScheme: ColorScheme? =
        ProcessInfo.processInfo.arguments.contains(LaunchArguments.darkMode) ? .dark : nil

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
            Group {
                switch store {
                case .success(let loaded):
                    AppRootView()
                        .environment(\.services, loaded.services)
                        .modelContainer(loaded.container)
                case .failure(let error):
                    StoreUnavailableView(error: error)
                }
            }
            // nil follows the system setting; only the UI-test walk forces dark.
            .preferredColorScheme(forcedScheme)
        }
    }
}
