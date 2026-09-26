import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 15: CSV import (owner decision 24). Parsing, reading amounts and dates, the preview, and the one-save
/// import.
struct CSVImportTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }
    private let cad = try! Currency(code: "CAD")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    // MARK: Parsing

    @Test func parserHandlesQuotesLineEndingsBOMAndBlankLines() throws {
        let text =
            "\u{FEFF}Date,Description,Amount\r\n2026-09-01,\"Café, \"\"Luna\"\"\",-4.50\r\n\r\n"
            + "2026-09-02,\"Two\nlines\",10\n"
        let rows = try CSVParser.parse(text)
        let expected = [
            ["Date", "Description", "Amount"], ["2026-09-01", "Café, \"Luna\"", "-4.50"],
            ["2026-09-02", "Two\nlines", "10"],
        ]
        #expect(rows == expected)
    }

    @Test func parserDetectsSemicolonsAndRefusesBrokenFiles() throws {
        let semicolons = try CSVParser.parse("Fecha;Importe\n01/09/2026;-4,50")
        #expect(semicolons == [["Fecha", "Importe"], ["01/09/2026", "-4,50"]])
        #expect(throws: CSVParser.Failure.unterminatedQuote(line: 2)) { try CSVParser.parse("a,b\n\"open,1") }
        #expect(throws: CSVParser.Failure.empty) { try CSVParser.parse("\n\n") }
        let many = "a\n" + String(repeating: "1\n", count: CSVParser.maximumRows + 1)
        #expect(throws: CSVParser.Failure.tooManyRows(CSVParser.maximumRows)) { try CSVParser.parse(many) }
    }

    @Test(arguments: [
        ("-12.50", Int64(-1_250)), ("12.50-", -1_250), ("(12.50)", -1_250), ("$1,234.56", 123_456),
        ("1.234,56", 123_456), ("1 234,56", 123_456), ("CA$ -7", -700), ("+3.5", 350), ("1,234", 123_400),
        ("12.500", 1_250),
    ])
    func amountsReadAsBanksWriteThem(text: String, expected: Int64) {
        #expect(CSVAmount.signedMinorUnits(text, currency: cad) == expected)
    }

    @Test(arguments: ["", "abc", "12-34-56", "1..2x", "--"])
    func nonAmountsAreRefused(text: String) {
        #expect(CSVAmount.signedMinorUnits(text, currency: cad) == nil)
    }

    @Test func datesReadInEachFormatAndAmbiguityIsLeftToTheUser() {
        #expect(CSVDateFormat.yearMonthDay.date(from: "2026-09-25", calendar: calendar) == day(2026, 9, 25))
        #expect(CSVDateFormat.monthDayYear.date(from: "09/25/2026", calendar: calendar) == day(2026, 9, 25))
        #expect(CSVDateFormat.dayMonthYear.date(from: "25.09.26", calendar: calendar) == day(2026, 9, 25))
        #expect(CSVDateFormat.yearMonthDay.date(from: "2026-02-30", calendar: calendar) == nil)
        #expect(CSVDateFormat.candidates(for: ["09/25/2026", "10/01/2026"], calendar: calendar) == [.monthDayYear])
        #expect(
            CSVDateFormat.candidates(for: ["03/04/2026"], calendar: calendar) == [.monthDayYear, .dayMonthYear],
            "Both readings work: the user picks")
    }

    @Test func columnsAreGuessedFromEnglishAndSpanishHeaders() {
        #expect(
            CSVMapping.guessColumns(header: ["Transaction Date", "Payee", "Amount", "Category"])
                == [.date: 0, .description: 1, .amount: 2, .category: 3])
        #expect(
            CSVMapping.guessColumns(header: ["Fecha", "Concepto", "Importe"])
                == [.date: 0, .description: 1, .amount: 2])
        #expect(CSVMapping.guessColumns(header: ["a", "b"]).isEmpty)
    }

    // MARK: Preview

    private let dining = CSVImportCategory(id: UUID(), name: "Dining", kind: .expense)
    private let salary = CSVImportCategory(id: UUID(), name: "Salary", kind: .income)

    private func preview(
        _ rows: [[String]], positiveSpending: Bool = false, existing: [CSVExistingTransaction] = []
    ) -> [CSVPreviewRow] {
        let mapping = CSVMapping(
            columns: [.date: 0, .description: 1, .amount: 2, .category: 3], dateFormat: .yearMonthDay,
            spendingIsPositive: positiveSpending)
        return CSVImportPlanner.preview(
            dataRows: rows, mapping: mapping, currency: cad, categories: [dining, salary], existing: existing,
            calendar: calendar)
    }

    @Test func previewReadsTypesCategoriesAndSkipsWithReasons() {
        let result = preview([
            ["2026-09-01", "Luna", "-4.50", "dining"],
            ["2026-09-02", "Pay", "3000", "Salary"],
            ["2026-09-03", "Refund", "20", "Dining"],  // income can't go under an expense-only category
            ["", "No date", "-1", ""],
            ["2026-13-01", "Bad date", "-1", ""],
            ["2026-09-04", "No amount", "", ""],
            ["2026-09-04", "Zero", "0.00", ""],
            ["2026-09-04", "Words", "ten", ""],
        ])
        #expect(result.map(\.line) == Array(2...9), "Lines count from the header")
        let luna = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: "Luna",
            categoryID: dining.id)
        #expect(result[0].row == luna)
        #expect(result[1].row?.type == .income && result[1].row?.categoryID == salary.id)
        #expect(result[2].row?.type == .income && result[2].row?.categoryID == nil, "Uncategorized")
        let reasons = result.dropFirst(3).map { row -> CSVSkipReason? in
            if case .failure(let error) = row.outcome { return error.reason }
            return nil
        }
        let expected: [CSVSkipReason?] = [
            .missingDate, .unreadableDate("2026-13-01"), .missingAmount, .zeroAmount, .unreadableAmount("ten"),
        ]
        #expect(reasons == expected)
    }

    @Test func spendingCanBePositiveAndDuplicatesAreFlagged() {
        let flipped = preview([["2026-09-01", "Luna", "4.50", ""]], positiveSpending: true)
        #expect(flipped.first?.row?.type == .expense)

        let existing = [
            CSVExistingTransaction(
                occurredAt: day(2026, 9, 1).addingTimeInterval(-3 * 3600), amount: money(450), type: .expense,
                text: "LUNA")
        ]
        let rows = preview(
            [["2026-09-01", "Luna", "-4.50", ""], ["2026-09-02", "Luna", "-4.50", ""]], existing: existing)
        #expect(rows.map(\.isLikelyDuplicate) == [true, false], "Same day, amount, type and words")
    }

    // MARK: Import

    private func makeLedger() async throws -> (ModelContainer, TransactionService, UUID) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let main = try #require(try await ledger.settingsSnapshot()?.defaultAccountID)
        return (container, ledger, main)
    }

    @Test func importSavesEveryRowAsImportedInOneAccount() async throws {
        let (container, ledger, main) = try await makeLedger()
        let rows = [
            CSVImportRow(
                occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: "Luna", categoryID: nil),
            CSVImportRow(
                occurredAt: day(2026, 9, 2), amount: money(300_000), type: .income, description: nil, categoryID: nil),
        ]
        #expect(try await ledger.importTransactions(rows, into: main, now: now) == 2)
        let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.source == .imported && $0.accountID == main && $0.status == .posted })
        #expect(records.allSatisfy { $0.merchantID == nil }, "Descriptions go to notes; no merchants are made")
        let seen = try await ledger.existingForImport(from: day(2026, 9, 1), to: day(2026, 9, 1), calendar: calendar)
        #expect(seen.map(\.text) == ["Luna"])
    }

    @Test func aRefusedRowImportsNothing() async throws {
        let (container, ledger, main) = try await makeLedger()
        let good = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: "Luna", categoryID: nil)
        let unknownCategory = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: "X", categoryID: UUID())
        await #expect(throws: LedgerError.unknownCategory) {
            try await ledger.importTransactions([good, unknownCategory], into: main, now: now)
        }
        let usd = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: Money(minorUnits: 100, currencyCode: "USD"), type: .expense,
            description: nil, categoryID: nil)
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await ledger.importTransactions([good, usd], into: main, now: now)
        }
        await #expect(throws: LedgerError.unknownAccount) {
            try await ledger.importTransactions([good], into: UUID(), now: now)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
    }
}
