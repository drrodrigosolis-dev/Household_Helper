import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 15: CSV import (owner decision 24) and its data-safety review: anything that could be misread is skipped
/// with a reason, never guessed.
struct CSVImportTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }
    private let cad = try! Currency(code: "CAD")
    private let jpy = try! Currency(code: "JPY")
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
            + "2026-09-02,\"Two\nlines\",10\n2026-09-03,After,1\n"
        let records = try CSVParser.records(text)
        let expected = [
            CSVRecord(line: 1, fields: ["Date", "Description", "Amount"]),
            CSVRecord(line: 2, fields: ["2026-09-01", "Café, \"Luna\"", "-4.50"]),
            CSVRecord(line: 4, fields: ["2026-09-02", "Two\nlines", "10"]),
            CSVRecord(line: 6, fields: ["2026-09-03", "After", "1"]),
        ]
        #expect(records == expected, "Lines are the file's, past blank lines and multi-line fields")
    }

    @Test func parserDetectsSemicolonsAndRefusesBrokenFiles() throws {
        let semicolons = try CSVParser.parse("Fecha;Importe\n01/09/2026;-4,50")
        #expect(semicolons == [["Fecha", "Importe"], ["01/09/2026", "-4,50"]])
        #expect(throws: CSVParser.Failure.unterminatedQuote(line: 2)) { try CSVParser.parse("a,b\n\"open,1") }
        #expect(throws: CSVParser.Failure.empty) { try CSVParser.parse("\n\n") }
        let many = "a\n" + String(repeating: "1\n", count: CSVParser.maximumRows + 1)
        #expect(throws: CSVParser.Failure.tooManyRows(CSVParser.maximumRows)) { try CSVParser.parse(many) }
        let big = Data(repeating: 65, count: CSVParser.maximumBytes + 1)
        #expect(throws: CSVParser.Failure.tooLarge) { try CSVParser.decode(big) }
        #expect(try CSVParser.decode(Data([0x43, 0x61, 0x66, 0xE9])) == "Café", "Latin-1 fallback")
    }

    @Test func theAppsOwnExportIsRecognized() {
        #expect(CSVParser.isHouseholdHubExport(header: TransactionCSV.header))
        #expect(!CSVParser.isHouseholdHubExport(header: ["Date", "Amount"]))
    }

    // MARK: Amounts

    // ((text, decimal mark), expected minor units)
    @Test(arguments: [
        (("-12.50", Character(".")), Int64(-1_250)), (("12.50-", "."), -1_250), (("(12.50)", "."), -1_250),
        (("$1,234.56", "."), 123_456), (("1.234,56", ","), 123_456), (("1 234,56", ","), 123_456),
        (("CA$ -7", "."), -700), (("+3.5", "."), 350), (("1,234", "."), 123_400), (("1.234", ","), 123_400),
        (("12.500", "."), 1_250), (("100.00 DR", "."), -10_000), (("100.00 CR", "."), 10_000),
        (("12.50 CAD", "."), 1_250), (("1,000,000.00", "."), 100_000_000),
    ])
    func amountsReadAsBanksWriteThem(input: (String, Character), expected: Int64) {
        #expect(CSVAmount.signedMinorUnits(input.0, currency: cad, decimalMark: input.1) == expected)
    }

    @Test(arguments: [
        ("", Character(".")), ("abc", "."), ("12-34-56", "."), ("1..2", "."), ("--", "."),
        ("1.234", "."),  // three decimals in a two-decimal currency: 1,234 or 1.234? Not guessed.
        ("12.505", "."),  // a real third decimal would be rounded away
        ("12.5.3", "."), ("1,2,3", "."), ("12,34.56", "."),  // groups must be threes
        ("12.50 USD", "."), ("US$12", "."), ("1.5E3", "."),  // other currencies and exponents
        ("(-12.50)", "."), ("-12.50-", "."), ("-12.50 DR", "."),  // one sign marker only
        ("99999999999999999999", "."),  // would overflow
        ("١٢٣", "."),  // non-ASCII digits
    ])
    func unclearAmountsAreRefused(text: String, mark: Character) {
        #expect(CSVAmount.signedMinorUnits(text, currency: cad, decimalMark: mark) == nil)
    }

    @Test func currenciesWithoutDecimalsRefuseFractions() {
        #expect(CSVAmount.signedMinorUnits("1,200", currency: jpy, decimalMark: ".") == 1_200)
        #expect(CSVAmount.signedMinorUnits("12.50", currency: jpy, decimalMark: ".") == nil)
        #expect(CSVAmount.signedMinorUnits("12.00", currency: jpy, decimalMark: ".") == 12)
    }

    @Test func theDecimalMarkIsDetectedOnlyWhenTheValuesSayIt() {
        #expect(CSVAmount.detectDecimalMark(["-4.50", "1,234.56"]) == ".")
        #expect(CSVAmount.detectDecimalMark(["-4,50", "12"]) == ",")
        #expect(CSVAmount.detectDecimalMark(["1,234", "12"]) == nil)
        #expect(CSVAmount.detectDecimalMark(["4.50", "4,50"]) == nil, "Conflicting files are the user's call")
    }

    // MARK: Dates

    // ((format, text), reads as 2026-09-25)
    @Test(arguments: [
        ((CSVDateFormat.yearMonthDay, "2026-09-25"), true), ((.monthDayYear, "09/25/2026"), true),
        ((.dayMonthYear, "25.09.26"), true), ((.yearMonthDay, "2026-09-25T10:30:00"), true),
        ((.yearMonthDay, "2026-02-30"), false), ((.monthDayYear, "13/01/2026"), false),
        ((.yearMonthDay, "2026-9"), false),
    ])
    func datesReadAsCalendarDays(input: (CSVDateFormat, String), readable: Bool) {
        let date = input.0.date(from: input.1, calendar: calendar)
        #expect((date != nil) == readable)
        if readable {
            #expect(date == day(2026, 9, 25))
        }
    }

    @Test func twoDigitYearsAndAmbiguityAreLeftToTheRules() {
        #expect(CSVDateFormat.dayMonthYear.date(from: "01/01/99", calendar: calendar) == day(1999, 1, 1))
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
            decimalMark: ".", spendingIsPositive: positiveSpending)
        let records = rows.enumerated().map { CSVRecord(line: $0.offset + 2, fields: $0.element) }
        return CSVImportPlanner.preview(
            records: records, headerCount: 4, mapping: mapping, currency: cad, categories: [dining, salary],
            existing: existing, calendar: calendar)
    }

    private func reasons(_ rows: [CSVPreviewRow]) -> [CSVSkipReason?] {
        rows.map { row in
            if case .failure(let error) = row.outcome { return error.reason }
            return nil
        }
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
            ["2026-09-04", "Reference", "123456789012", ""],
            ["2026-09-01", "Store", " 12", "-4.50", "1000.00"],  // an unquoted comma shifted the columns
            ["2026-09-05", "Trailing", "-1.00", "", ""],  // a trailing separator is fine
        ])
        let luna = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: "Luna",
            categoryID: dining.id)
        #expect(result[0].row == luna)
        #expect(result[1].row?.type == .income && result[1].row?.categoryID == salary.id)
        #expect(result[2].row?.type == .income && result[2].row?.categoryID == nil, "Uncategorized")
        #expect(result[10].row?.amount == money(100))
        let expected: [CSVSkipReason?] = [
            nil, nil, nil, .missingDate, .unreadableDate("2026-13-01"), .missingAmount, .zeroAmount,
            .unreadableAmount("ten"), .amountTooLarge("123456789012"), .columnCount(expected: 4, found: 5), nil,
        ]
        #expect(reasons(result) == expected)
    }

    @Test func spendingCanBePositiveAndDuplicatesAreFlaggedPrecisely() {
        let flipped = preview([["2026-09-01", "Luna", "4.50", ""]], positiveSpending: true)
        #expect(flipped.first?.row?.type == .expense)

        let existing = [
            CSVExistingTransaction(
                occurredAt: day(2026, 9, 1).addingTimeInterval(-3 * 3600), amount: money(450), type: .expense,
                text: "LUNA")
        ]
        let rows = preview(
            [
                ["2026-09-01", "Luna", "-4.50", ""],  // same day, amount, type, words
                ["2026-09-02", "Luna", "-4.50", ""],  // another day
                ["2026-09-01", "Luna", "-4.51", ""],  // another amount
                ["2026-09-01", "Luna", "4.50", ""],  // income, not an expense
                ["2026-09-01", "Sol", "-4.50", ""],  // other words
            ], existing: existing)
        #expect(rows.map(\.isLikelyDuplicate) == [true, false, false, false, false])
    }

    // MARK: Import

    private func makeLedger() async throws -> (ModelContainer, TransactionService, UUID) {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        let main = try #require(try await ledger.settingsSnapshot()?.defaultAccountID)
        return (container, ledger, main)
    }

    private func row(
        _ description: String?, _ minorUnits: Int64, _ type: TransactionType = .expense
    ) -> CSVImportRow {
        CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(minorUnits), type: type, description: description,
            categoryID: nil)
    }

    @Test func importSavesEveryRowAsImportedInOneAccountAndSurvivesABackup() async throws {
        let (container, ledger, main) = try await makeLedger()
        let count = try await ledger.importTransactions(
            [row("Luna", 450), row(nil, 300_000, .income)], into: main, now: now)
        #expect(count == 2)
        let records = try ModelContext(container).fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.source == .imported && $0.accountID == main && $0.status == .posted })
        #expect(records.allSatisfy { $0.merchantID == nil }, "Descriptions go to notes; no merchants are made")

        let service = BackupService.make(container: container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        try BackupValidator.validate(backup)
        #expect(backup.transactions.allSatisfy { $0.source == TransactionSource.imported.rawValue })
    }

    @Test func theDuplicateCheckSeesOnlyLiveTransactionsInTheAccount() async throws {
        let (_, ledger, main) = try await makeLedger()
        let savings = AccountDraft(
            name: "Savings", kind: .savings, startingBalance: money(0), startingBalanceDate: day(2026, 1, 1))
        let other = try await ledger.createAccount(savings, now: now)
        try await ledger.importTransactions([row("Luna", 450)], into: main, now: now)
        try await ledger.importTransactions([row("Elsewhere", 450)], into: other, now: now)
        let cancelled = TransactionDraft(
            amount: money(700), type: .expense, occurredAt: day(2026, 9, 1), status: .cancelled, notes: "Cancelled")
        try await ledger.create(cancelled, now: now)
        let seen = try await ledger.existingForImport(
            accountID: main, from: day(2026, 9, 1), to: day(2026, 9, 1), calendar: calendar)
        #expect(seen.map(\.text) == ["Luna"])
    }

    @Test func aRefusedRowImportsNothing() async throws {
        let (container, ledger, main) = try await makeLedger()
        let categories = CategoryService.make(container: container)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        let salaryID = try #require(all.first { $0.name == "Salary" }).id
        let good = row("Luna", 450)
        let wrongKind = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: nil, categoryID: salaryID)
        let usd = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: Money(minorUnits: 100, currencyCode: "USD"), type: .expense,
            description: nil, categoryID: nil)
        let unknownCategory = CSVImportRow(
            occurredAt: day(2026, 9, 1), amount: money(450), type: .expense, description: nil, categoryID: UUID())
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await ledger.importTransactions([good, wrongKind], into: main, now: now)
        }
        await #expect(throws: LedgerError.unknownCategory) {
            try await ledger.importTransactions([good, unknownCategory], into: main, now: now)
        }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await ledger.importTransactions([good, usd], into: main, now: now)
        }
        await #expect(throws: LedgerError.amountTooLarge) {
            try await ledger.importTransactions([good, row(nil, Money.maxPlanMinorUnits + 1)], into: main, now: now)
        }
        await #expect(throws: LedgerError.unknownAccount) {
            try await ledger.importTransactions([good], into: UUID(), now: now)
        }
        let savings = try await ledger.createAccount(
            AccountDraft(name: "Old", kind: .savings, startingBalance: money(0), startingBalanceDate: day(2026, 1, 1)),
            now: now)
        try await ledger.setAccountArchived(true, account: savings, now: now)
        await #expect(throws: LedgerError.archivedAccount) {
            try await ledger.importTransactions([good], into: savings, now: now)
        }
        let tooMany = Array(repeating: good, count: CSVParser.maximumRows + 1)
        await #expect(throws: CSVParser.Failure.tooManyRows(CSVParser.maximumRows)) {
            try await ledger.importTransactions(tooMany, into: main, now: now)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
    }
}
