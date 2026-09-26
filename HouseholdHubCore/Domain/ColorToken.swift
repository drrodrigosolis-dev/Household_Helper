import Foundation

/// Persistable sRGB color (spec §7.3). Never a serialized SwiftUI `Color`.
public struct ColorToken: Codable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? (value << 8) | 0xFF : value
        let red = UInt8((full >> 24) & 0xFF)
        let green = UInt8((full >> 16) & 0xFF)
        let blue = UInt8((full >> 8) & 0xFF)
        self.init(red: red, green: green, blue: blue, alpha: UInt8(full & 0xFF))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X%02X", Int(red), Int(green), Int(blue), Int(alpha))
    }

    public static let white = ColorToken(red: 255, green: 255, blue: 255)
    public static let black = ColorToken(red: 0, green: 0, blue: 0)

    /// WCAG 2.x relative luminance of the opaque color.
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrastRatio(with other: ColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG AA: 4.5:1 for body text, 3:1 for large text and non-text UI.
    public func meetsAAContrast(against background: ColorToken, largeText: Bool = false) -> Bool {
        contrastRatio(with: background) >= (largeText ? 3 : 4.5)
    }

    /// Where an accent color used for buttons and links falls below 3:1 against the list backgrounds it sits on.
    public enum AccentVisibility: Equatable, Sendable {
        case fine
        case hardInLightMode
        case hardInDarkMode
    }

    /// Checked against white (Light Mode) and the dark grouped background (Dark Mode). Every color reaches 3:1
    /// against at least one of them, so a color is never hard to see in both.
    public var accentVisibility: AccentVisibility {
        if contrastRatio(with: .white) < 3 { return .hardInLightMode }
        if contrastRatio(with: .darkSecondaryBackground) < 3 { return .hardInDarkMode }
        return .fine
    }

    /// iOS's secondary grouped background in Dark Mode, where the Analytics chart sits.
    public static let darkSecondaryBackground = ColorToken(red: 0x1C, green: 0x1C, blue: 0x1E)

    /// This color, mixed toward white (on a dark background) or black (on a light one) in small steps only as far as
    /// needed to reach `minimum` contrast, so a chart mark stays distinguishable from its background (WCAG 1.4.11).
    /// Colors that already meet it come back unchanged.
    public func ensuringContrast(against background: ColorToken, minimum: Double = 3) -> ColorToken {
        guard contrastRatio(with: background) < minimum else { return self }
        let target: ColorToken = background.relativeLuminance < 0.5 ? .white : .black
        for step in 1...20 {
            let candidate = mixed(with: target, fraction: Double(step) / 20)
            if candidate.contrastRatio(with: background) >= minimum {
                return candidate
            }
        }
        return target
    }

    private func mixed(with other: ColorToken, fraction: Double) -> ColorToken {
        func channel(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * fraction).rounded())
        }
        return ColorToken(
            red: channel(red, other.red), green: channel(green, other.green), blue: channel(blue, other.blue),
            alpha: alpha)
    }
}
