import HouseholdHubCore
import SwiftUI
import UIKit

/// Sprint 21: the drawings, doodles and chalk surfaces that dress a theme (owner's Toy Box mockup, decision 30).
/// Drawings come from the owner's art boards (`Assets.xcassets/ThemeArt`, cut by `Scripts/cut-theme-art.py` from
/// `docs/theme-art/<theme>.json`); a piece a theme has no drawing for is drawn as a code doodle instead.
///
/// Each case is a spot the app draws in, not a subject: Toy Box's `header1` is its bear, Dinosaurs' its long-neck.
enum ThemePiece: String, CaseIterable {
    /// The corner drawings on a tab's first screen (Toy Box: sun, cloud, rainbow, heart).
    case cornerTopLeading, cornerTopTrailing, cornerBottomLeading, cornerBottomTrailing
    /// The row of drawings under the Dashboard title, left to right.
    case header1, header2, header3, header4
    /// Small accents beside card titles.
    case star, starSmall
    /// Under the Dashboard title.
    case underline
    /// Beside the 30-day projection (Toy Box: the car) and on Recent activity (the blocks).
    case ornamentWide, ornamentActivity
    /// The floating Quick Add button.
    case addButton
}

/// Small drawings made in code: every theme has them, with or without an art board.
enum Doodle {
    case star
    case heart
    case snowflake
    case squiggle
    /// Three short strokes fanning out, like the lines beside the balance in the mockup.
    case dashes
}

/// Crayon colors shared by every theme's doodles; the theme's accent covers the rest.
enum ThemeInk {
    static let yellow = Color(red: 0.95, green: 0.76, blue: 0.31)
    static let blue = Color(red: 0.42, green: 0.62, blue: 0.93)
    /// Card outlines: pale blue chalk on the dark board, graphite on the light paper.
    static let outline = Color(light: token("#4A4A58", alpha: 110), dark: token("#8FB0E8", alpha: 150))

    private static func token(_ hex: String, alpha: UInt8) -> ColorToken {
        var token = ColorToken(hex: hex) ?? .black
        token.alpha = alpha
        return token
    }
}

extension ThemeSpec {
    /// The drawing from this theme's art board, or nil while its board has not been cut.
    func art(_ piece: ThemePiece) -> Image? {
        UIImage(named: artName(piece)).map { Image(uiImage: $0) }
    }

    /// The asset's name in `ThemeArt`, as `Scripts/cut-theme-art.py` writes it: `<theme>-<piece>`.
    func artName(_ piece: ThemePiece) -> String {
        "\(theme.rawValue.lowercased())-\(piece.rawValue)"
    }

    /// The doodle a theme scatters where there is no drawing.
    var doodle: Doodle {
        switch theme {
        case .loveMom: .heart
        case .winter: .snowflake
        case .off, .toyBox, .airplanes, .dinosaurs: .star
        }
    }
}

// MARK: - Chalk outline

/// A rounded rectangle traced by hand: the edge wobbles a little, differently for each `seed`.
struct ChalkOutline: Shape {
    var cornerRadius: CGFloat
    var seed: Double

    func path(in rect: CGRect) -> Path {
        let radius = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
        let straightWidth = rect.width - 2 * radius
        let straightHeight = rect.height - 2 * radius
        let arc = CGFloat.pi / 2 * radius
        let perimeter = 2 * (straightWidth + straightHeight) + 4 * arc
        guard perimeter > 0 else { return Path() }
        let count = max(32, Int(perimeter / 5))
        var path = Path()
        // A little past the start, as a hand-drawn line overlaps where it began.
        for index in 0...(count + 3) {
            let distance = perimeter * CGFloat(index) / CGFloat(count)
            let edge = Self.point(at: distance, in: rect, radius: radius, arc: arc)
            let phase = CGFloat(seed)
            let wobble = sin(distance * 0.045 + phase) * 0.9 + sin(distance * 0.13 + phase * 2.3) * 0.5
            let shifted = CGPoint(x: edge.point.x + edge.normal.dx * wobble, y: edge.point.y + edge.normal.dy * wobble)
            if index == 0 {
                path.move(to: shifted)
            } else {
                path.addLine(to: shifted)
            }
        }
        return path
    }

    private struct EdgePoint {
        let point: CGPoint
        let normal: CGVector
    }

    /// The point `distance` along the edge, clockwise from the top edge's left end, and the outward normal there.
    private static func point(at distance: CGFloat, in rect: CGRect, radius: CGFloat, arc: CGFloat) -> EdgePoint {
        let width = rect.width - 2 * radius
        let height = rect.height - 2 * radius
        var left = distance.truncatingRemainder(dividingBy: 2 * (width + height) + 4 * arc)
        func edge(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) -> EdgePoint {
            EdgePoint(point: CGPoint(x: x, y: y), normal: CGVector(dx: dx, dy: dy))
        }
        func corner(_ centerX: CGFloat, _ centerY: CGFloat, from start: CGFloat) -> EdgePoint {
            let angle = start + (radius > 0 ? left / radius : 0)
            return edge(centerX + cos(angle) * radius, centerY + sin(angle) * radius, cos(angle), sin(angle))
        }
        if left < width { return edge(rect.minX + radius + left, rect.minY, 0, -1) }
        left -= width
        if left < arc { return corner(rect.maxX - radius, rect.minY + radius, from: -.pi / 2) }
        left -= arc
        if left < height { return edge(rect.maxX, rect.minY + radius + left, 1, 0) }
        left -= height
        if left < arc { return corner(rect.maxX - radius, rect.maxY - radius, from: 0) }
        left -= arc
        if left < width { return edge(rect.maxX - radius - left, rect.maxY, 0, 1) }
        left -= width
        if left < arc { return corner(rect.minX + radius, rect.maxY - radius, from: .pi / 2) }
        left -= arc
        if left < height { return edge(rect.minX, rect.maxY - radius - left, -1, 0) }
        left -= height
        return corner(rect.minX + radius, rect.minY + radius, from: .pi)
    }
}

/// The mockup's card edge: two chalk passes that don't quite agree.
struct ChalkBorder: View {
    let cornerRadius: CGFloat
    var color: Color = ThemeInk.outline

    var body: some View {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        ZStack {
            ChalkOutline(cornerRadius: cornerRadius, seed: 0.7).stroke(color, style: style)
            ChalkOutline(cornerRadius: max(0, cornerRadius - 2), seed: 3.1)
                .stroke(color.opacity(0.55), style: style)
                .padding(2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Doodles

struct DoodleShape: Shape {
    let doodle: Doodle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = min(rect.width, rect.height)
        switch doodle {
        case .star:
            let outer = size / 2
            let inner = outer * 0.45
            for index in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let length = index.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        case .heart:
            let top = rect.minY + size * 0.3
            path.move(to: CGPoint(x: center.x, y: rect.minY + size * 0.95))
            path.addCurve(
                to: CGPoint(x: center.x, y: top), control1: CGPoint(x: rect.minX - size * 0.1, y: center.y),
                control2: CGPoint(x: center.x - size * 0.2, y: rect.minY - size * 0.1))
            path.addCurve(
                to: CGPoint(x: center.x, y: rect.minY + size * 0.95),
                control1: CGPoint(x: center.x + size * 0.2, y: rect.minY - size * 0.1),
                control2: CGPoint(x: rect.maxX + size * 0.1, y: center.y))
        case .snowflake:
            let arm = size / 2
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3
                let tip = CGPoint(x: center.x + cos(angle) * arm, y: center.y + sin(angle) * arm)
                path.move(to: center)
                path.addLine(to: tip)
                let branch = CGPoint(x: center.x + cos(angle) * arm * 0.6, y: center.y + sin(angle) * arm * 0.6)
                for side: CGFloat in [-1, 1] {
                    let branchAngle = angle + side * .pi / 4
                    path.move(to: branch)
                    path.addLine(
                        to: CGPoint(
                            x: branch.x + cos(branchAngle) * arm * 0.3, y: branch.y + sin(branchAngle) * arm * 0.3))
                }
            }
        case .squiggle:
            path.move(to: CGPoint(x: rect.minX, y: center.y))
            let steps = 24
            for index in 1...steps {
                let fraction = CGFloat(index) / CGFloat(steps)
                path.addLine(
                    to: CGPoint(
                        x: rect.minX + rect.width * fraction,
                        y: center.y + sin(fraction * .pi * 4) * rect.height * 0.3))
            }
        case .dashes:
            for (index, angle) in [CGFloat(-0.45), 0, 0.45].enumerated() {
                let start = CGPoint(x: rect.minX + size * 0.1, y: center.y + CGFloat(index - 1) * size * 0.3)
                let length = size * 0.55
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
            }
        }
        return path
    }
}

/// A doodle in crayon: filled for stars and hearts, a line for the rest.
struct DoodleView: View {
    let doodle: Doodle
    var color: Color = ThemeInk.yellow
    var size: CGFloat = 18

    var body: some View {
        let style = StrokeStyle(lineWidth: max(1.5, size / 10), lineCap: .round, lineJoin: .round)
        DoodleShape(doodle: doodle)
            .stroke(color, style: style)
            .frame(width: doodle == .squiggle ? size * 2.5 : size, height: size)
            .accessibilityHidden(true)
    }
}

/// A drawing from the art board where the theme has one; otherwise the theme's doodle.
struct ThemeDrawing: View {
    @Environment(\.funTheme) private var theme
    let piece: ThemePiece
    /// Height of the drawing; a fallback doodle is drawn a little smaller.
    let height: CGFloat

    var body: some View {
        if let theme {
            if let image = theme.art(piece) {
                image.resizable().scaledToFit().frame(height: height)
                    .accessibilityHidden(true)
            } else {
                DoodleView(doodle: theme.doodle, color: Self.fallbackColor(piece, theme), size: height * 0.55)
            }
        }
    }

    private static func fallbackColor(_ piece: ThemePiece, _ theme: ThemeSpec) -> Color {
        switch piece {
        case .star, .starSmall, .cornerTopLeading: ThemeInk.yellow
        case .cornerTopTrailing, .header2: ThemeInk.blue
        default: theme.accent
        }
    }
}

// MARK: - Screen

/// Chalkboard (dark) or paper (light): the theme's background with a faint, fixed grain and a few smudges.
struct ThemeTexture: View {
    @Environment(\.colorScheme) private var colorScheme
    let background: Color

    var body: some View {
        let ink: Color = colorScheme == .dark ? .white : .black
        Canvas(rendersAsynchronously: true) { context, size in
            var generator = SeededGenerator(seed: 21)
            var smudges = context
            smudges.addFilter(.blur(radius: 30))
            for _ in 0..<7 {
                let origin = CGPoint(
                    x: CGFloat.random(in: -80...size.width, using: &generator),
                    y: CGFloat.random(in: 0...size.height, using: &generator))
                let extent = CGSize(
                    width: CGFloat.random(in: 120...260, using: &generator),
                    height: CGFloat.random(in: 40...90, using: &generator))
                let rect = CGRect(origin: origin, size: extent)
                smudges.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.035)))
            }
            let specks = Int(size.width * size.height / 900)
            for _ in 0..<specks {
                let point = CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &generator),
                    y: CGFloat.random(in: 0...size.height, using: &generator))
                let length = CGFloat.random(in: 0.6...2.4, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(origin: point, size: CGSize(width: length, height: 0.8))),
                    with: .color(ink.opacity(Double.random(in: 0.03...0.09, using: &generator))))
            }
        }
        .background(background)
        .accessibilityHidden(true)
    }
}

/// The page behind a themed screen. `decorated` adds the corner drawings (sun, cloud, rainbow, heart) that frame a
/// tab's first screen in the mockup; pushed screens and sheets keep only the texture.
struct ThemeBackdrop: View {
    let theme: ThemeSpec
    let decorated: Bool
    /// Off on screens with toolbar buttons at the top right.
    var topTrailing = true

    var body: some View {
        ThemeTexture(background: theme.background)
            .overlay {
                if decorated {
                    ZStack {
                        ThemeDrawing(piece: .cornerTopLeading, height: 96)
                            .offset(x: -10, y: -4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        if topTrailing {
                            ThemeDrawing(piece: .cornerTopTrailing, height: 62)
                                .padding(.top, 56)
                                .padding(.trailing, 24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }
                        ThemeDrawing(piece: .cornerBottomLeading, height: 44)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        ThemeDrawing(piece: .cornerBottomTrailing, height: 34)
                            .padding(.trailing, 14)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .opacity(0.9)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Under a tab's large title: a crayon underline, then a row of the theme's drawings that bob gently (still with
/// Reduce Motion or theme animations off).
struct ThemeHeaderStrip: View {
    @Environment(\.funTheme) private var theme
    @Environment(\.themeAnimates) private var animates
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let row: [(ThemePiece, CGFloat)] = [
        (.star, 20), (.header1, 60), (.starSmall, 16), (.header2, 58), (.header3, 50), (.starSmall, 14), (.header4, 58),
    ]

    var body: some View {
        if let theme {
            VStack(alignment: .leading, spacing: 6) {
                underline(theme)
                if !typeSize.isAccessibilitySize {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { context in
                        let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
                        HStack(alignment: .center, spacing: 0) {
                            ForEach(Array(Self.row.enumerated()), id: \.offset) { index, item in
                                ThemeDrawing(piece: item.0, height: item.1)
                                    .offset(y: sin(time * 1.2 + Double(index) * 0.9) * 4)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 64)
                }
            }
            .padding(.top, -8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func underline(_ theme: ThemeSpec) -> some View {
        if let image = theme.art(.underline) {
            image.resizable().scaledToFit().frame(width: 190, alignment: .leading)
        } else {
            DoodleShape(doodle: .squiggle)
                .stroke(ThemeInk.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 170, height: 8)
        }
    }
}

// MARK: - Buttons

/// "+ Add" in the mockup's balance card: an accent crayon capsule.
struct CrayonCapsuleStyle: ButtonStyle {
    @Environment(\.funTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        let accent = theme?.accent ?? .accentColor
        configuration.label
            .themedFont(.subheadline, weight: .semibold)
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(accent.opacity(configuration.isPressed ? 0.3 : 0.16), in: Capsule())
            .overlay {
                ChalkBorder(cornerRadius: 40, color: accent)
            }
            .contentShape(Capsule())
    }
}

/// A small random number generator with a fixed seed, so the texture is the same on every draw.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
