import HouseholdHubCore
import SwiftUI

/// Sprint 19 (owner request): a theme also changes a few words, playful but still plain. Only presentation changes:
/// stored names are never rewritten. Money words (balance, pending, projected, §9), tab names and screen titles
/// never change.
extension FunTheme {
    /// How the three default columns read, in board order. Nil with themes off.
    var columnNames: [String]? {
        switch self {
        case .off:
            return nil
        case .toyBox:
            return [
                String(localized: "Waiting to play"), String(localized: "Playing"), String(localized: "Put away"),
            ]
        case .airplanes:
            return [
                String(localized: "Ready for takeoff"), String(localized: "Flying"), String(localized: "Landed"),
            ]
        case .dinosaurs:
            return [String(localized: "In the nest"), String(localized: "Hatching"), String(localized: "Hatched!")]
        case .loveMom:
            return [
                String(localized: "Sweet to-dos"), String(localized: "In the works"),
                String(localized: "Done with love"),
            ]
        case .winter:
            return [
                String(localized: "Bundling up"), String(localized: "Out in the snow"),
                String(localized: "Cozy by the fire"),
            ]
        }
    }

    /// Replaces "No tasks" in an empty column.
    var emptyColumnText: String? {
        switch self {
        case .off: nil
        case .toyBox: String(localized: "Toy box is empty")
        case .airplanes: String(localized: "Clear skies")
        case .dinosaurs: String(localized: "No eggs here")
        case .loveMom: String(localized: "Nothing here, sweetheart")
        case .winter: String(localized: "Fresh snow, no tracks")
        }
    }

    /// Replaces "No wishlist items yet" (not the filtered "Nothing matches", which must stay exact).
    var emptyWishlistTitle: String? {
        switch self {
        case .off: nil
        case .toyBox: String(localized: "Your wish box is empty")
        case .airplanes: String(localized: "No destinations yet")
        case .dinosaurs: String(localized: "No treasures dug up yet")
        case .loveMom: String(localized: "No wishes yet, love")
        case .winter: String(localized: "Your stocking is empty")
        }
    }

    /// Shown with a celebration burst.
    var celebrationText: String? {
        switch self {
        case .off: nil
        case .toyBox: String(localized: "Hooray!")
        case .airplanes: String(localized: "Smooth landing!")
        case .dinosaurs: String(localized: "Roar!")
        case .loveMom: String(localized: "Proud of you!")
        case .winter: String(localized: "Snow much fun!")
        }
    }
}

extension BoardColumn {
    /// The name shown on the board. A default column that still has its seeded name (English or Spanish) reads in
    /// the theme's words; a column the user created or renamed always shows its own name.
    func displayName(theme: ThemeSpec?) -> String {
        guard isSystem, let names = theme?.theme.columnNames,
            let slot = TaskBoardService.defaultColumnNames.firstIndex(of: name)
                ?? TaskBoardService.spanishColumnNames.firstIndex(of: name),
            slot < names.count
        else { return name }
        return names[slot]
    }
}
