import Foundation
import HouseholdHubCore
import Testing

@testable import HouseholdHub

/// Sprint 19: a theme renames only how things read. Stored names are never touched, and a column the user named
/// keeps its name.
@MainActor
struct ThemeWordingTests {
    static let themes = FunTheme.allCases.filter { $0 != .off }

    private func column(_ name: String, system: Bool = true) -> BoardColumn {
        BoardColumn(name: name, sortOrder: 0, isSystem: system, now: .now)
    }

    @Test func airplanesRenamesTheDefaultColumnsForDisplayOnly() {
        let spec = FunTheme.airplanes.spec
        let names = TaskBoardService.defaultColumnNames.map { column($0) }
        #expect(names.map { $0.displayName(theme: spec) } == ["Ready for takeoff", "Flying", "Landed"])
        #expect(names.map(\.name) == TaskBoardService.defaultColumnNames, "Stored names are never rewritten")
    }

    @Test func spanishSeedNamesAreRecognized() {
        let spec = FunTheme.airplanes.spec
        let shown = TaskBoardService.spanishColumnNames.map { column($0).displayName(theme: spec) }
        #expect(shown == ["Ready for takeoff", "Flying", "Landed"])
    }

    @Test(arguments: themes)
    func namesTheUserChoseAreKept(_ theme: FunTheme) {
        #expect(column("Errands", system: false).displayName(theme: theme.spec) == "Errands")
        #expect(column("Waiting on others").displayName(theme: theme.spec) == "Waiting on others")
        // A custom column that happens to be called "Done" is the user's, not the seeded one.
        #expect(column("Done", system: false).displayName(theme: theme.spec) == "Done")
    }

    @Test func offShowsStoredNames() {
        for name in TaskBoardService.defaultColumnNames {
            #expect(column(name).displayName(theme: FunTheme.off.spec) == name)
            #expect(column(name).displayName(theme: nil) == name)
        }
        #expect(FunTheme.off.emptyColumnText == nil)
        #expect(FunTheme.off.emptyWishlistTitle == nil)
        #expect(FunTheme.off.celebrationText == nil)
    }

    @Test(arguments: themes)
    func everyThemeHasAllItsWords(_ theme: FunTheme) {
        let columns = theme.columnNames ?? []
        #expect(columns.count == TaskBoardService.defaultColumnNames.count)
        #expect(Set(columns).count == columns.count, "Column names must differ")
        #expect(columns.allSatisfy { !$0.isEmpty && $0.count <= 20 }, "Short enough for a column header")
        #expect(theme.emptyColumnText?.isEmpty == false)
        #expect(theme.emptyWishlistTitle?.isEmpty == false)
        #expect(theme.celebrationText?.isEmpty == false)
    }
}
