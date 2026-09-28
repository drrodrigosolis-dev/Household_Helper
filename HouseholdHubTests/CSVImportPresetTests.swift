import Foundation
import Testing

@testable import HouseholdHubCore

/// Sprint 23 (F8): saved bank presets. A device setting in `UserDefaults`, matched by header names, never guessing an
/// account that no longer applies.
struct CSVImportPresetTests {
    private func preset(
        name: String = "My bank", accountID: UUID = UUID(),
        headerSignature: [String] = ["Date", "Description", "Amount"]
    ) -> CSVImportPreset {
        CSVImportPreset(
            name: name, columns: [.date: 0, .description: 1, .amount: 2], dateFormat: .yearMonthDay,
            decimalMark: ",", spendingIsPositive: true, accountID: accountID, headerSignature: headerSignature)
    }

    // MARK: Encoding

    @Test func encodingAndDecodingRoundTrips() throws {
        let original = preset()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CSVImportPreset.self, from: data)
        #expect(decoded == original)
        #expect(decoded.mapping.columns == original.columns)
        #expect(decoded.mapping.dateFormat == .yearMonthDay)
        #expect(decoded.mapping.decimalMark == ",")
        #expect(decoded.mapping.spendingIsPositive)
    }

    @Test func decodingIgnoresAnUnknownColumnRole() throws {
        let account = UUID()
        let json = """
            {"id":"\(UUID().uuidString)","name":"Old export","columns":{"date":0,"amount":1,"reference":2},\
            "dateFormat":"yearMonthDay","decimalMark":".","spendingIsPositive":false,\
            "accountID":"\(account.uuidString)","headerSignature":["Date","Amount","Ref"]}
            """
        let decoded = try JSONDecoder().decode(CSVImportPreset.self, from: Data(json.utf8))
        #expect(decoded.columns == [.date: 0, .amount: 1])
    }

    // MARK: Matching

    @Test func headerMatchingIgnoresCaseAndSurroundingWhitespace() {
        let saved = preset(headerSignature: ["Date", "Description", "Amount"])
        #expect(saved.matches(header: ["Date", "Description", "Amount"]))
        #expect(saved.matches(header: [" date ", "DESCRIPTION", "amount"]))
        #expect(!saved.matches(header: ["Amount", "Description", "Date"]), "Order matters: indices must still line up")
        #expect(!saved.matches(header: ["Date", "Description"]), "A different column count never matches")
        #expect(!saved.matches(header: ["Date", "Memo", "Amount"]))
    }

    // MARK: Applying

    @Test func unknownOrArchivedAccountsAreIgnoredWhenApplied() {
        let active = UUID()
        let archived = UUID()
        let stillActive = preset(accountID: active)
        let noLongerActive = preset(accountID: archived)
        #expect(stillActive.targetAccountID(activeAccountIDs: [active]) == active)
        #expect(noLongerActive.targetAccountID(activeAccountIDs: [active]) == nil, "Archived or deleted: ignored")
        #expect(noLongerActive.targetAccountID(activeAccountIDs: []) == nil)
    }

    // MARK: Store

    private func makeStore() -> CSVImportPresetStore {
        let suite = "CSVImportPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CSVImportPresetStore(defaults: defaults)
    }

    @Test func storeSavesListsAndDeletesPresets() {
        let store = makeStore()
        #expect(store.all().isEmpty)
        let first = preset(name: "Bank A")
        let second = preset(name: "Bank B", headerSignature: ["Fecha", "Concepto", "Importe"])
        store.save(first)
        store.save(second)
        #expect(Set(store.all().map(\.id)) == [first.id, second.id])

        var renamed = first
        renamed.name = "Bank A (renamed)"
        store.save(renamed)
        #expect(store.all().count == 2, "Saving an existing id replaces it, it doesn't duplicate")
        #expect(store.all().first { $0.id == first.id }?.name == "Bank A (renamed)")

        store.delete(id: second.id)
        #expect(store.all().map(\.id) == [first.id])
    }

    // MARK: Preview parity

    @Test func applyingAPresetReproducesTheSamePreviewAsMappingByHand() throws {
        let dining = CSVImportCategory(id: UUID(), name: "Dining", kind: .expense)
        let calendar = HouseholdCalendar(timeZone: try #require(TimeZone(identifier: "America/Vancouver")))
        let cad = try Currency(code: "CAD")
        let header = ["Fecha", "Concepto", "Importe", "Categoria"]
        let records = [
            CSVRecord(line: 2, fields: ["2026-09-01", "Luna", "-4,50", "Dining"]),
            CSVRecord(line: 3, fields: ["2026-09-02", "Pay", "3000", ""]),
        ]
        let handMapping = CSVMapping(
            columns: [.date: 0, .description: 1, .amount: 2, .category: 3], dateFormat: .yearMonthDay,
            decimalMark: ",", spendingIsPositive: false)
        let saved = CSVImportPreset(
            name: "Mi banco", columns: handMapping.columns, dateFormat: handMapping.dateFormat,
            decimalMark: handMapping.decimalMark, spendingIsPositive: handMapping.spendingIsPositive,
            accountID: UUID(), headerSignature: header)
        #expect(saved.matches(header: header))
        let byHand = CSVImportPlanner.preview(
            records: records, headerCount: header.count, mapping: handMapping, currency: cad, categories: [dining],
            existing: [], calendar: calendar)
        let byPreset = CSVImportPlanner.preview(
            records: records, headerCount: header.count, mapping: saved.mapping, currency: cad, categories: [dining],
            existing: [], calendar: calendar)
        #expect(byHand == byPreset)
    }

    @Test func storeFindsTheMatchingPresetByHeader() {
        let store = makeStore()
        let bankA = preset(name: "Bank A", headerSignature: ["Date", "Amount"])
        let bankB = preset(name: "Bank B", headerSignature: ["Fecha", "Importe"])
        store.save(bankA)
        store.save(bankB)
        #expect(store.matching(header: [" fecha ", "IMPORTE"])?.name == "Bank B")
        #expect(store.matching(header: ["Nothing", "Like", "It"]) == nil)
    }
}
