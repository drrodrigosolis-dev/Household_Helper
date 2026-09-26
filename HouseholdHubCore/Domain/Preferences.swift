import Foundation

/// Light, dark, or following the system (spec §7.11 `selectedTheme`).
public enum ThemePreference: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// Which kind of entry Quick Add opens on (spec §7.11 `defaultQuickAddType`).
public enum QuickAddType: String, Codable, Sendable, CaseIterable {
    case expense
    case income
    case wishlist
    case task
}
