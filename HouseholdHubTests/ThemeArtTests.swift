import CoreGraphics
import HouseholdHubCore
import Testing
import UIKit

@testable import HouseholdHub

/// Sprint 21: every theme's drawings are in the catalog under the names the cutter writes (a missing one is drawn as
/// a doodle), and the hand-drawn card edge stays on its card.
@MainActor
struct ThemeArtTests {
    /// What each theme's boards don't have (it draws a doodle there): only Toy Box's mockup had a crayon add button,
    /// and only Toy Box and Love Mom have an underline stroke.
    nonisolated static let missing: [FunTheme: Set<ThemePiece>] = [
        .toyBox: [],
        .loveMom: [.addButton],
        .airplanes: [.addButton, .underline],
        .dinosaurs: [.addButton, .underline],
        .winter: [.addButton, .underline],
    ]

    @Test(arguments: FunTheme.allCases.filter { $0 != .off })
    func everyThemeHasItsDrawings(_ theme: FunTheme) throws {
        let spec = try #require(theme.spec)
        let gaps = try #require(Self.missing[theme], "\(theme) has no entry")
        for piece in ThemePiece.allCases {
            let exists = UIImage(named: spec.artName(piece)) != nil
            #expect(exists == !gaps.contains(piece), "\(spec.artName(piece)) exists: \(exists)")
        }
    }

    @Test func assetNamesMatchTheCutter() throws {
        let spec = try #require(FunTheme.toyBox.spec)
        #expect(spec.artName(.addButton) == "toybox-addButton")
        #expect(try #require(FunTheme.loveMom.spec).artName(.header1) == "lovemom-header1")
    }

    @Test func eachThemeHasItsOwnDoodle() throws {
        #expect(try #require(FunTheme.loveMom.spec).doodle == .heart)
        #expect(try #require(FunTheme.winter.spec).doodle == .snowflake)
        #expect(try #require(FunTheme.toyBox.spec).doodle == .star)
    }

    @Test(arguments: [CGSize(width: 340, height: 120), CGSize(width: 44, height: 20), CGSize(width: 1, height: 1)])
    func chalkOutlineStaysOnItsCard(_ size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        for seed in [0.7, 3.1] {
            let bounds = ChalkOutline(cornerRadius: 16, seed: seed).path(in: rect).boundingRect
            #expect(!bounds.isEmpty || size.width <= 1)
            #expect(rect.insetBy(dx: -2, dy: -2).contains(bounds), "\(bounds) strays from \(rect)")
        }
    }

    @Test func textureIsTheSameOnEveryDraw() {
        var first = SeededGenerator(seed: 21)
        var second = SeededGenerator(seed: 21)
        let a = (0..<8).map { _ in first.next() }
        let b = (0..<8).map { _ in second.next() }
        #expect(a == b)
        #expect(Set(a).count == a.count)
    }
}
