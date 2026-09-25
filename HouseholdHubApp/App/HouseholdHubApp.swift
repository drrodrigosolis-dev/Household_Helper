import HouseholdHubCore
import SwiftData
import SwiftUI

@main
struct HouseholdHubApp: App {
    private let container: Result<ModelContainer, any Error>

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
        let configuration = PersistenceConfiguration(useInMemoryStore: inMemory)
        container = Result { try HouseholdContainerFactory().makeContainer(configuration: configuration) }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                AppRootView()
                    .modelContainer(container)
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}
