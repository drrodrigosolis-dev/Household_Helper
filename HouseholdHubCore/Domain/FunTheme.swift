import Foundation

/// Sprint 19: the fun themes chosen in Settings › Appearance › Style. A device setting, not stored in SwiftData or
/// backups. Everything a theme draws is data here (colors, the name of a font iOS ships, SF Symbol names, emoji), so
/// no font or image file is bundled and the catalog is testable without SwiftUI.
public enum FunTheme: String, CaseIterable, Identifiable, Sendable {
    /// The original look.
    case off
    case toyBox
    case airplanes
    case dinosaurs
    case loveMom
    case winter

    public var id: String { rawValue }

    /// Nil for `off`.
    public var spec: ThemeSpec? { ThemeSpec.catalog[self] }

    /// The stored choice, falling back to `off` for anything unknown (a value from a newer build, say).
    public init(storedValue: String) {
        self = FunTheme(rawValue: storedValue) ?? .off
    }
}

/// The tabs whose icon a theme replaces. Budget and More keep theirs so money and settings stay easy to find.
public enum ThemedTab: CaseIterable, Sendable {
    case dashboard
    case wishlist
    case tasks
}

/// The Dashboard's gentle background animation.
public enum AmbientMotion: Sendable {
    /// Glyphs bob in place.
    case bobbing
    /// One glyph crosses the screen now and then.
    case crossing
    /// Glyphs step across the bottom edge.
    case walking
    /// Glyphs rise and fade.
    case floatingUp
    /// Glyphs fall slowly.
    case falling
}

/// The colors a theme paints in one appearance. Text keeps the system label colors; the tests hold every palette to
/// the contrast those need.
public struct ThemePalette: Hashable, Sendable {
    /// Tint for buttons, links and switches; also the fill behind white text on prominent buttons.
    public let accent: ColorToken
    /// Screen background.
    public let background: ColorToken
    /// Cards, list rows and columns drawn on the background.
    public let surface: ColorToken

    public init(accent: ColorToken, background: ColorToken, surface: ColorToken) {
        self.accent = accent
        self.background = background
        self.surface = surface
    }
}

public struct ThemeSpec: Sendable {
    public let theme: FunTheme
    public let light: ThemePalette
    public let dark: ThemePalette
    /// PostScript name of a font iOS ships, used for titles, headings, big numbers and tab names.
    public let titleFont: String
    /// SF Symbol names.
    public let tabSymbols: [ThemedTab: String]
    /// Shown above an empty list.
    public let emptyStateGlyph: String
    public let ambient: AmbientMotion
    public let ambientGlyphs: [String]
    /// Burst when a task is completed, a wishlist item is bought, or a savings goal is reached.
    public let celebrationGlyphs: [String]

    public func palette(dark isDark: Bool) -> ThemePalette { isDark ? dark : light }

    static let catalog: [FunTheme: ThemeSpec] = Dictionary(
        uniqueKeysWithValues: [toyBox, airplanes, dinosaurs, loveMom, winter].map { ($0.theme, $0) })

    private static func color(_ hex: String) -> ColorToken {
        guard let token = ColorToken(hex: hex) else { preconditionFailure("Bad theme color \(hex)") }
        return token
    }

    private static func palette(_ accent: String, _ background: String, _ surface: String) -> ThemePalette {
        ThemePalette(accent: color(accent), background: color(background), surface: color(surface))
    }

    /// Primary red, yellow and blue; generic toys only.
    static let toyBox = ThemeSpec(
        theme: .toyBox,
        light: palette("#C8102E", "#FFF6D6", "#FFFFFF"),
        dark: palette("#E0342F", "#101C3D", "#1B2A55"),
        titleFont: "ChalkboardSE-Bold",
        tabSymbols: [.dashboard: "teddybear", .wishlist: "gift", .tasks: "puzzlepiece"],
        emptyStateGlyph: "🧸",
        ambient: .bobbing,
        ambientGlyphs: ["🧸", "🪁", "🧩", "🚀"],
        celebrationGlyphs: ["🧱", "⭐️", "🎈", "🧸"])

    /// Sky blue, cloud white, sunset orange.
    static let airplanes = ThemeSpec(
        theme: .airplanes,
        light: palette("#0B63B6", "#EAF5FF", "#FFFFFF"),
        dark: palette("#D9661A", "#0B1A2E", "#15294A"),
        titleFont: "AvenirNext-Heavy",
        tabSymbols: [.dashboard: "airplane", .wishlist: "suitcase.rolling", .tasks: "map"],
        emptyStateGlyph: "✈️",
        ambient: .crossing,
        ambientGlyphs: ["✈️", "☁️"],
        celebrationGlyphs: ["✈️", "🛩️", "🌍", "🧳"])

    /// Fern green, amber, volcano red.
    static let dinosaurs = ThemeSpec(
        theme: .dinosaurs,
        light: palette("#2E7D32", "#F1F8E4", "#FFFFFF"),
        dark: palette("#3E8E41", "#132015", "#1E3222"),
        titleFont: "MarkerFelt-Wide",
        tabSymbols: [.dashboard: "lizard", .wishlist: "leaf", .tasks: "pawprint"],
        emptyStateGlyph: "🦕",
        ambient: .walking,
        ambientGlyphs: ["🐾"],
        celebrationGlyphs: ["🦕", "🦖", "🥚", "🌋", "🌿"])

    /// Rose, lavender, cream.
    static let loveMom = ThemeSpec(
        theme: .loveMom,
        light: palette("#C2185B", "#FFF0F5", "#FFFFFF"),
        dark: palette("#D6457F", "#24121D", "#351C2B"),
        titleFont: "BradleyHandITCTT-Bold",
        tabSymbols: [.dashboard: "heart.circle", .wishlist: "gift", .tasks: "list.bullet.clipboard"],
        emptyStateGlyph: "💐",
        ambient: .floatingUp,
        ambientGlyphs: ["💗", "🌸", "💐"],
        celebrationGlyphs: ["💖", "🌷", "💐", "💌", "🎁"])

    /// Ice blue, pine green, berry red.
    static let winter = ThemeSpec(
        theme: .winter,
        light: palette("#1E6091", "#EEF6FB", "#FFFFFF"),
        dark: palette("#2F80C0", "#0C1624", "#172638"),
        titleFont: "Noteworthy-Bold",
        tabSymbols: [.dashboard: "snowflake", .wishlist: "gift", .tasks: "mug"],
        emptyStateGlyph: "⛄️",
        ambient: .falling,
        ambientGlyphs: ["❄️"],
        celebrationGlyphs: ["❄️", "⛄️", "🧤", "🎄", "☕️"])
}
