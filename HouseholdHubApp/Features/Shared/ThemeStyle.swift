import HouseholdHubCore
import SwiftUI
import UIKit

/// Sprint 19: the fun theme is a device setting (`@AppStorage`), not app data: it is not in SwiftData or backups.
enum ThemeSettings {
    static let themeKey = "funTheme"
    static let animationsKey = "funThemeAnimations"

    /// UI tests start from the original look: a choice made by an earlier test run is forgotten. A test that needs a
    /// theme passes `-funTheme <name>`, which lives in the arguments domain and is not removed here.
    static func resetForUITesting() {
        UserDefaults.standard.removeObject(forKey: themeKey)
        UserDefaults.standard.removeObject(forKey: animationsKey)
    }

    static var storedTheme: FunTheme {
        FunTheme(storedValue: UserDefaults.standard.string(forKey: themeKey) ?? "")
    }
}

extension EnvironmentValues {
    /// Nil when themes are off.
    @Entry var funTheme: ThemeSpec? = nil
    /// Theme animations are on in Settings and Reduce Motion is off.
    @Entry var themeAnimates: Bool = false
}

extension FunTheme {
    var displayName: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .toyBox: "Toy Box"
        case .airplanes: "Airplanes"
        case .dinosaurs: "Dinosaurs"
        case .loveMom: "Love Mom"
        case .winter: "Winter Special"
        }
    }
}

extension ThemeSpec {
    var accent: Color { Color(light: light.accent, dark: dark.accent) }
    var background: Color { Color(light: light.background, dark: dark.background) }
    var surface: Color { Color(light: light.surface, dark: dark.surface) }

    /// The theme's display font at the size of `style`, scaling with Dynamic Type like the system style.
    func displayFont(_ style: Font.TextStyle) -> Font {
        .custom(titleFont, size: Self.baseSize(style), relativeTo: style)
    }

    /// Point sizes of the text styles at the default Dynamic Type size.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

extension Color {
    /// A color that follows the light or dark appearance.
    init(light: ColorToken, dark: ColorToken) {
        let lightColor = UIColor(token: light)
        let darkColor = UIColor(token: dark)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

extension UIColor {
    convenience init(token: ColorToken) {
        self.init(
            red: CGFloat(token.red) / 255, green: CGFloat(token.green) / 255, blue: CGFloat(token.blue) / 255,
            alpha: CGFloat(token.alpha) / 255)
    }
}

extension View {
    /// Titles, headings and big numbers take the theme's font; with themes off, the system style.
    func themedFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ThemedFont(style: style, weight: weight))
    }

    /// A card or column: the theme's surface color, or `standard` (the original fill) with themes off.
    func themedSurface(cornerRadius: CGFloat, standard: some ShapeStyle) -> some View {
        modifier(ThemedSurface(cornerRadius: cornerRadius, standard: AnyShapeStyle(standard)))
    }

    /// A list row drawn as a chalk-edged card on the theme's page (Sprint 21); the system row with themes off.
    func themedRow() -> some View {
        modifier(ThemedRow())
    }

    /// The theme's page behind a screen (Sprint 21: chalkboard or paper). Every pushed or presented screen applies it
    /// next to its title; a tab's first screen passes `decorated` for the corner drawings.
    func themedScreen(decorated: Bool = false) -> some View {
        modifier(ThemedScreen(decorated: decorated))
    }
}

private struct ThemedFont: ViewModifier {
    @Environment(\.funTheme) private var theme
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        let font = theme?.displayFont(style) ?? .system(style)
        // The root sets SF Rounded for body text with a theme on, and a font design overrides a custom font (Sprint 19
        // walk: titles came out SF Rounded). Clearing it here changes nothing with themes off, where none is set.
        content.font(weight.map { font.weight($0) } ?? font).fontDesign(nil)
    }
}

private struct ThemedSurface: ViewModifier {
    @Environment(\.funTheme) private var theme
    let cornerRadius: CGFloat
    let standard: AnyShapeStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if let theme {
            // Sprint 21: a chalk-sketched edge, as in the owner's mockup.
            content
                .background(theme.surface.opacity(0.92), in: shape)
                .overlay { ChalkBorder(cornerRadius: cornerRadius) }
        } else {
            content.background(standard, in: shape)
        }
    }
}

private struct ThemedRow: ViewModifier {
    @Environment(\.funTheme) private var theme

    func body(content: Content) -> some View {
        content.listRowBackground(theme.map { ThemedRowBackground(surface: $0.surface) })
    }
}

private struct ThemedRowBackground: View {
    let surface: Color

    var body: some View {
        surface.opacity(0.92)
            .overlay { ChalkBorder(cornerRadius: 12).padding(.vertical, 2).padding(.horizontal, 1) }
    }
}

/// An empty state's title and picture: the theme's picture when a theme is on, else the given symbol.
struct EmptyStateLabel: View {
    @Environment(\.funTheme) private var theme
    let title: Text
    let systemImage: String

    init(_ title: Text, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if let theme {
            Label {
                title
            } icon: {
                Text(theme.emptyStateGlyph).accessibilityHidden(true)
            }
        } else {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.funTheme) private var theme
    let decorated: Bool

    func body(content: Content) -> some View {
        if let theme {
            content.containerBackground(for: .navigation) { ThemeBackdrop(theme: theme, decorated: decorated) }
        } else {
            content
        }
    }
}

/// Navigation bar and tab titles are UIKit's; SwiftUI has no font for them. The appearance proxies cover bars made
/// from now on, and the bars already on screen are updated in place so a new choice shows without relaunching.
@MainActor
enum ThemeAppearance {
    static func apply(_ theme: ThemeSpec?) {
        let large = theme.flatMap { font($0.titleFont, style: .largeTitle, size: 34) }
        let inline = theme.flatMap { font($0.titleFont, style: .headline, size: 17) }
        let tab = theme.flatMap { font($0.titleFont, style: .caption2, size: 10) }
        let largeAttributes: [NSAttributedString.Key: Any]? = large.map { [.font: $0] }
        let inlineAttributes: [NSAttributedString.Key: Any]? = inline.map { [.font: $0] }
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = largeAttributes
        navigationBar.titleTextAttributes = inlineAttributes
        UITabBarItem.appearance().setTitleTextAttributes(tab.map { [.font: $0] }, for: .normal)
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            for bar in navigationBars(in: window) {
                bar.largeTitleTextAttributes = largeAttributes
                bar.titleTextAttributes = inlineAttributes
                bar.setNeedsLayout()
            }
        }
    }

    private static func font(_ name: String, style: UIFont.TextStyle, size: CGFloat) -> UIFont? {
        UIFont(name: name, size: size).map { UIFontMetrics(forTextStyle: style).scaledFont(for: $0) }
    }

    private static func navigationBars(in view: UIView) -> [UINavigationBar] {
        let own = (view as? UINavigationBar).map { [$0] } ?? []
        return own + view.subviews.flatMap(navigationBars(in:))
    }
}
