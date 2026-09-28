import CoreGraphics
import HouseholdHubCore
import Testing
import UIKit

@testable import HouseholdHub

/// Sprint 21: the Toy Box drawings are in the catalog under the names the cutter writes, a theme without a board
/// falls back to doodles, and the hand-drawn card edge stays on its card.
@MainActor
struct ThemeArtTests {
    nonisolated static let pieces = ThemePiece.allCases

    @Test(arguments: pieces)
    func toyBoxHasEveryDrawing(_ piece: ThemePiece) throws {
        let spec = try #require(FunTheme.toyBox.spec)
        #expect(UIImage(named: spec.artName(piece)) != nil, "\(spec.artName(piece)) is missing from ThemeArt")
    }

    @Test func assetNamesMatchTheCutter() throws {
        let spec = try #require(FunTheme.toyBox.spec)
        #expect(spec.artName(.addButton) == "toybox-addButton")
        #expect(try #require(FunTheme.loveMom.spec).artName(.sun) == "lovemom-sun")
    }

    /// Until the owner's boards for the other themes are cut, they draw doodles.
    @Test func themesWithoutABoardUseTheirDoodle() throws {
        for theme in [FunTheme.airplanes, .dinosaurs, .loveMom, .winter] {
            let spec = try #require(theme.spec)
            #expect(spec.art(.bear) == nil, "\(theme) has no art board yet")
        }
        #expect(try #require(FunTheme.loveMom.spec).doodle == .heart)
        #expect(try #require(FunTheme.winter.spec).doodle == .snowflake)
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
