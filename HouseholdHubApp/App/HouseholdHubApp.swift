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
        if inMemory {
            ThemeSettings.resetForUITesting()
            TutorialSettings.resetForUITesting()
        }
        // Before the first navigation bar is made, so it already has the theme's title font.
        ThemeAppearance.apply(ThemeSettings.storedTheme.spec)
        // Sprint 24: loads the tips datastore once; hidden under -uiTesting unless -uiTestingTips asks otherwise.
        TutorialTips.configure()
        store = Result {
            let container = try HouseholdContainerFactory().makeContainer(configuration: configuration)
            return LoadedStore(container: container, services: AppServices(container: container))
        }
        SharedServices.current = try? store.get().services
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
        }
    }
}
