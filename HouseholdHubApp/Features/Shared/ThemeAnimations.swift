import HouseholdHubCore
import SwiftUI

/// Sprint 19: a celebration is requested where something good happened (a task done, a wishlist item bought, a
/// savings goal reached) and drawn once, over the whole app, by `CelebrationOverlay`.
@MainActor
@Observable
final class Celebration {
    static let shared = Celebration()
    private(set) var count = 0

    func fire() {
        count += 1
    }
}

/// A burst of the theme's pictures rising from the bottom of the screen, with a short cheer. Nothing with themes off,
/// Theme animations off, or Reduce Motion (`themeAnimates`). Hidden from VoiceOver (the cheer is announced), never
/// takes a tap.
struct CelebrationOverlay: View {
    @Environment(\.funTheme) private var theme
    @Environment(\.themeAnimates) private var animates
    @State private var burst: Int?
    @State private var launched = false

    private let celebration = Celebration.shared

    var body: some View {
        GeometryReader { proxy in
            if let theme, animates, let burst {
                ForEach(0..<14, id: \.self) { index in
                    let glyph = theme.celebrationGlyphs[index % theme.celebrationGlyphs.count]
                    Text(glyph)
                        .font(.system(size: 34))
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 60)
                        .offset(launched ? Self.flight(index, in: proxy.size) : .zero)
                        .scaleEffect(launched ? 1.3 : 0.4)
                        .opacity(launched ? 0 : 1)
                }
                .id(burst)
                if let caption = theme.theme.celebrationText {
                    Text(caption)
                        .themedFont(.title, weight: .bold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.4)
                        .opacity(launched ? 0 : 1)
                        .animation(.easeIn(duration: 0.5).delay(0.9), value: launched)
                        .id(burst)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: celebration.count) { _, count in
            guard animates, theme != nil else { return }
            launched = false
            burst = count
            // The burst is decorative and hidden from VoiceOver; its words are announced instead.
            if let caption = theme?.theme.celebrationText {
                AccessibilityNotification.Announcement(caption).post()
            }
            Task {
                // One frame at the start position, then fly.
                try? await Task.sleep(for: .milliseconds(20))
                withAnimation(.easeOut(duration: 1.4)) { launched = true }
                try? await Task.sleep(for: .milliseconds(1500))
                if burst == count { burst = nil }
            }
        }
    }

    /// Fans out upward, each piece at its own angle and distance.
    private static func flight(_ index: Int, in size: CGSize) -> CGSize {
        let angle = Double.pi * (0.1 + 0.8 * Double(index) / 13)
        let reach = size.height * (0.35 + 0.2 * Double(index % 3) / 2)
        return CGSize(width: cos(angle) * size.width * 0.45, height: -sin(angle) * reach)
    }
}

extension AmbientMotion {
    /// Motions that live near one edge would sit behind the cards on a full Dashboard (Sprint 19 walk: toys,
    /// footprints and hearts were hidden), so they get their own strip above the cards. A plane crossing and falling
    /// snow cover the whole screen and show between the cards.
    var drawsInBanner: Bool {
        switch self {
        case .bobbing, .walking, .floatingUp: true
        case .crossing, .falling: false
        }
    }
}

/// The Dashboard's gentle animation, faint: in a strip above the cards (`.banner`) or behind them (`.background`),
/// depending on the theme's motion. With Theme animations off or Reduce Motion it stands still.
struct AmbientLayer: View {
    enum Placement {
        case banner
        case background
    }

    @Environment(\.funTheme) private var theme
    @Environment(\.themeAnimates) private var animates
    let placement: Placement

    var body: some View {
        if let theme, theme.ambient.drawsInBanner == (placement == .banner) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { context in
                let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
                GeometryReader { proxy in
                    ForEach(Self.pieces(theme, at: time, in: proxy.size)) { piece in
                        Text(piece.glyph)
                            .font(.system(size: piece.size))
                            .position(piece.point)
                            .opacity(piece.opacity)
                    }
                }
            }
            .opacity(placement == .banner ? 0.8 : 0.35)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    struct Piece: Identifiable {
        let id: Int
        let glyph: String
        let point: CGPoint
        let size: CGFloat
        var opacity: Double = 1
    }

    /// Where each picture is at `time`: a pure function, so the layer keeps no state.
    static func pieces(_ theme: ThemeSpec, at time: TimeInterval, in size: CGSize) -> [Piece] {
        let glyphs = theme.ambientGlyphs
        func glyph(_ index: Int) -> String { glyphs[index % glyphs.count] }
        func fraction(_ value: Double) -> Double { value - value.rounded(.down) }
        let width = size.width
        let height = size.height
        switch theme.ambient {
        case .bobbing:
            return (0..<4).map { index in
                let x = width * (0.14 + 0.24 * Double(index))
                let y = height * 0.5 + sin(time * 1.3 + Double(index)) * 6
                return Piece(id: index, glyph: glyph(index), point: CGPoint(x: x, y: y), size: 30)
            }
        case .crossing:
            let plane = Piece(
                id: 0, glyph: glyph(0),
                point: CGPoint(x: fraction(time / 16) * (width + 80) - 40, y: height * 0.22 + sin(time) * 8),
                size: 34)
            let clouds = (1...3).map { index in
                let x = fraction(Double(index) / 3 + time / 60) * (width + 60) - 30
                return Piece(
                    id: index, glyph: glyph(1), point: CGPoint(x: x, y: height * (0.12 + 0.1 * Double(index))),
                    size: 28)
            }
            return clouds + [plane]
        case .walking:
            let step = time / 0.7
            return (0..<6).map { index in
                let age = fraction((step - Double(index)) / 9) * 9
                let x = width * (Double(index) + 0.5) / 6
                let y = height * 0.5 + (index.isMultiple(of: 2) ? -6 : 6)
                return Piece(
                    id: index, glyph: glyph(index), point: CGPoint(x: x, y: y), size: 22,
                    opacity: max(0, 1 - age / 4))
            }
        case .floatingUp:
            return (0..<5).map { index in
                let progress = fraction((time + Double(index) * 1.8) / 9)
                let x = width * (0.1 + 0.2 * Double(index)) + sin(time + Double(index)) * 10
                return Piece(
                    id: index, glyph: glyph(index), point: CGPoint(x: x, y: height * (1 - progress)), size: 24,
                    opacity: sin(progress * .pi))
            }
        case .falling:
            return (0..<12).map { index in
                let speed = 0.04 + 0.02 * Double(index % 3)
                let progress = fraction(time * speed + Double(index) * 0.37)
                let x = width * fraction(Double(index) * 0.618) + sin(time * 0.8 + Double(index)) * 12
                return Piece(
                    id: index, glyph: glyph(index), point: CGPoint(x: x, y: height * progress),
                    size: CGFloat(16 + 6 * (index % 3)))
            }
        }
    }
}
