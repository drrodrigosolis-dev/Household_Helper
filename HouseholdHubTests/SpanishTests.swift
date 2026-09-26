import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 16: Spanish (owner decision 25). Quick Add understands Spanish words whatever the device language, new data
/// set up in Spanish gets Spanish names, and the app's String Catalog has a Spanish value for every key.
struct SpanishTests {
    private let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    /// Friday 2026-09-25 15:00 in Vancouver.
    private let now = Date(timeIntervalSince1970: 1_790_373_600)

    private var parser: QuickAddParser {
        QuickAddParser(currency: try! Currency(code: "CAD"), categories: [], calendar: calendar)
    }

    @Test(arguments: [
        ("47.50 café ayer", TransactionType.expense, "café", 1),
        ("ingreso 1200 salario", .income, "salario", 0),
        ("Recibí 50 regalo", .income, "regalo", 0),
        ("gasto 12 taxi hoy", .expense, "taxi", 0),
        ("18 almuerzo miércoles", .expense, "almuerzo", 2),
        ("18 almuerzo MIE", .expense, "almuerzo", 2),
        ("30 cena sáb", .expense, "cena", 6),
    ])
    func quickAddReadsSpanishWords(text: String, type: TransactionType, description: String, daysBack: Int) {
        let parsed = parser.parse(text, now: now)
        #expect(parsed.type == type)
        #expect(parsed.description == description)
        let expected = calendar.calendar.date(byAdding: .day, value: -daysBack, to: now)
        #expect(parsed.occurredAt == expected)
    }

    @Test func seedLanguageFollowsTheFirstPreferredLanguage() {
        #expect(SeedLanguage.preferred(["es-MX", "en-CA"]) == .spanish)
        #expect(SeedLanguage.preferred(["en-CA", "es-MX"]) == .english)
        #expect(SeedLanguage.preferred([]) == .english)
    }

    @Test func newDataSetUpInSpanishHasSpanishNames() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        await ledger.setSeedLanguage(.spanish)
        try await categories.seedSystemCategoriesIfNeeded(now: now, language: .spanish)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let context = ModelContext(container)
        let names = Set(try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.name))
        #expect(names.contains("Supermercado") && names.contains("Salario") && names.contains("Otros ingresos"))
        #expect(!names.contains("Groceries"))
        #expect(try context.fetch(FetchDescriptor<Account>()).map(\.name) == ["Cuenta principal"])
        try await TaskBoardService.make(container: container).seedDefaultColumnsIfNeeded(now: now, language: .spanish)
        let columns = try context.fetch(FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(columns.map(\.name) == ["Por hacer", "En curso", "Hecho"])
        let untranslated = SystemCategory.defaults.filter { $0.name(in: .spanish) == $0.name }
        #expect(untranslated.isEmpty, "Every seed has a Spanish name")
    }

    /// The catalog is valid JSON, every key has a Spanish value, and every value keeps the key's placeholders.
    @Test func theStringCatalogIsCompleteAndKeepsPlaceholders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in [
            "HouseholdHubApp/Resources/Localizable.xcstrings", "HouseholdHubWidget/Localizable.xcstrings",
            "HouseholdHubApp/Resources/AppShortcuts.xcstrings", "HouseholdHubApp/Resources/InfoPlist.xcstrings",
        ] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(catalog["strings"] as? [String: [String: Any]])
            #expect(!strings.isEmpty, "\(path) is empty")
            for (key, entry) in strings {
                let localizations = entry["localizations"] as? [String: [String: Any]]
                let unit = localizations?["es"]?["stringUnit"] as? [String: String]
                let value = try #require(unit?["value"], "\(path): no Spanish for “\(key)”")
                #expect(!value.isEmpty)
                #expect(placeholders(key) == placeholders(value), "\(path): placeholders differ in “\(key)”")
            }
        }
    }

    /// Placeholders by kind, ignoring order and positions ("%2$lld" counts as "%lld").
    private func placeholders(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(lld|@|d|lf)/).map { "%" + String($0.output.1) }.sorted()
    }
}
