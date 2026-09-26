import HouseholdHubCore
import WidgetKit

/// Writes the widget's snapshot into the App Group container and asks WidgetKit to reload (spec §5.2). Without an
/// App Group (the free Personal Team) there is nowhere to write and the widget shows its fixture, so this does
/// nothing. A failure only leaves the widget with older figures; it never touches the store.
enum WidgetSync {
    @MainActor
    static func refresh(_ services: AppServices?) async {
        guard let services, let store = WidgetSnapshotStore.appGroup(AppInfo.appGroupIdentifier),
            let snapshot = try? await services.transactions.widgetSnapshot(
                now: .now, calendar: HouseholdCalendar(timeZone: .current))
        else { return }
        try? store.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
}
