import Testing
import UIKit

@testable import HouseholdHubCore

/// Sprint 19: every theme is complete, readable in light and dark, and draws only what iOS ships.
struct FunThemeTests {
    static let themes = FunTheme.allCases.compactMap(\.spec)
    private static let white = ColorToken.white
    private static let black = ColorToken.black

    @Test func everyThemeButOffHasASpec() {
        #expect(FunTheme.off.spec == nil)
        #expect(Self.themes.count == FunTheme.allCases.count - 1)
        for spec in Self.themes {
            #expect(spec.theme.spec?.theme == spec.theme)
        }
    }

    @Test func anUnknownStoredValueFallsBackToOff() {
        #expect(FunTheme(storedValue: "toyBox") == .toyBox)
        #expect(FunTheme(storedValue: "") == .off)
        #expect(FunTheme(storedValue: "spaceship") == .off)
    }

    /// Body text uses the system label color (black in light, white in dark): 4.5:1 on backgrounds and surfaces.
    @Test(arguments: themes)
    func labelsAreReadable(_ spec: ThemeSpec) {
        for surface in [spec.light.background, spec.light.surface] {
            #expect(Self.black.meetsAAContrast(against: surface), "\(spec.theme) light \(surface.hex)")
        }
        for surface in [spec.dark.background, spec.dark.surface] {
            #expect(Self.white.meetsAAContrast(against: surface), "\(spec.theme) dark \(surface.hex)")
        }
    }

    /// Secondary text is the system's translucent gray. In dark it must reach 4.5:1; in light iOS's own secondary
    /// label on its grouped background is 3.3:1, and a theme may not go below that.
    @Test(arguments: themes)
    func secondaryTextIsNoHarderToReadThanStock(_ spec: ThemeSpec) {
        let stockLight = Self.secondary(on: ColorToken(hex: "#F2F2F7")!, dark: false)
        for surface in [spec.light.background, spec.light.surface] {
            let ratio = Self.secondary(on: surface, dark: false)
            #expect(ratio >= stockLight - 0.01, "\(spec.theme) light \(surface.hex): \(ratio)")
        }
        for surface in [spec.dark.background, spec.dark.surface] {
            let ratio = Self.secondary(on: surface, dark: true)
            #expect(ratio >= 4.5, "\(spec.theme) dark \(surface.hex): \(ratio)")
        }
    }

    /// The accent is a control color (3:1 on what it sits on) and the fill behind white text on prominent buttons
    /// (3:1, which stock iOS blue in dark also meets and no more: 3.65:1).
    @Test(arguments: themes)
    func accentIsVisibleAndCarriesWhiteText(_ spec: ThemeSpec) {
        for (mode, palette) in [("light", spec.light), ("dark", spec.dark)] {
            for surface in [palette.background, palette.surface] {
                #expect(palette.accent.contrastRatio(with: surface) >= 3, "\(spec.theme) \(mode) on \(surface.hex)")
            }
            #expect(palette.accent.contrastRatio(with: Self.white) >= 3, "\(spec.theme) \(mode) under white text")
        }
    }

    /// Only fonts iOS ships (zero cost, nothing bundled).
    @Test(arguments: themes)
    func titleFontShipsWithIOS(_ spec: ThemeSpec) {
        #expect(UIFont(name: spec.titleFont, size: 17) != nil, "\(spec.titleFont) is not installed")
    }

    @Test(arguments: themes)
    func tabSymbolsExist(_ spec: ThemeSpec) {
        for tab in ThemedTab.allCases {
            let name = spec.tabSymbols[tab]
            #expect(name != nil, "\(spec.theme) has no symbol for \(tab)")
            if let name {
                #expect(UIImage(systemName: name) != nil, "\(name) is not an SF Symbol")
            }
        }
    }

    @Test(arguments: themes)
    func everyThemeHasPictures(_ spec: ThemeSpec) {
        #expect(!spec.emptyStateGlyph.isEmpty)
        #expect(!spec.ambientGlyphs.isEmpty)
        #expect(spec.celebrationGlyphs.count >= 3)
    }

    @Test func themesLookDifferent() {
        #expect(Set(Self.themes.map(\.light.accent)).count == Self.themes.count)
        #expect(Set(Self.themes.map(\.titleFont)).count == Self.themes.count)
    }

    /// Contrast of iOS's secondary label (60% of #3C3C43 in light, of #EBEBF5 in dark) composited on `surface`.
    private static func secondary(on surface: ColorToken, dark: Bool) -> Double {
        let ink =
            dark ? ColorToken(red: 0xEB, green: 0xEB, blue: 0xF5) : ColorToken(red: 0x3C, green: 0x3C, blue: 0x43)
        func blend(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * 0.6).rounded())
        }
        let composite = ColorToken(
            red: blend(surface.red, ink.red), green: blend(surface.green, ink.green),
            blue: blend(surface.blue, ink.blue))
        return composite.contrastRatio(with: surface)
    }
}
