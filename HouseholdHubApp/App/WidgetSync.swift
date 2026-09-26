import HouseholdHubCore
import WidgetKit

/// Writes the widget's snapshot into the App Group container and asks WidgetKit to reload (spec §5.2). Without an
/// App Group (the free Personal Team) there is nowhere to write and the widget shows its fixture, so this does
/// nothing. A failure only leaves the widget with older figures; it never touches the store.
enum WidgetSync {
    @MainActor
    static func refresh(_ services: AppServices?) async {
        // UI tests run on a throwaway in-memory store; they must never replace the real widget's file.
        guard !ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting) else { return }
        guard let services, let store = WidgetSnapshotStore.appGroup(AppInfo.appGroupIdentifier) else { return }
        let now = Date.now
        // If the figures can't be computed, replace the old file with an amount-free one rather than leave amounts
        // the user may just have hidden.
        let snapshot =
            (try? await services.transactions.widgetSnapshot(now: now, calendar: HouseholdCalendar(timeZone: .current)))
            ?? .placeholder(now: now)
        try? store.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
}
