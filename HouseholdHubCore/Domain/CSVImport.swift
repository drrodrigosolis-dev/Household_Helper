import Foundation

/// One CSV record and the file line it starts on (1-based), so messages point at what a spreadsheet shows even when
/// blank lines were dropped or a quoted field spans lines.
public struct CSVRecord: Equatable, Sendable {
    public let line: Int
    public let fields: [String]

    public init(line: Int, fields: [String]) {
        self.line = line
        self.fields = fields
    }
}

/// Reads CSV text (RFC 4180): quoted fields with doubled quotes, CRLF or LF, a leading BOM, and comma or semicolon
/// separators (whichever the header line uses more of). Sprint 15, owner decision 24.
public enum CSVParser {
    public static let maximumBytes = 5 * 1024 * 1024
    public static let maximumRows = 5_000

    public enum Failure: Error, Equatable, Sendable {
        case empty
        case tooLarge
        case tooManyRows(Int)
        case unterminatedQuote(line: Int)
        case notText
    }

    /// The file's bytes as text: refused above `maximumBytes` (checked on the bytes, before decoding), UTF-8 or
    /// Latin-1 (older bank exports).
    public static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw Failure.notText
        }
        return text
    }

    /// Fields of each non-blank record, header first.
    public static func parse(_ text: String) throws -> [[String]] {
        try records(text).map(\.fields)
    }

    /// Non-blank records with their starting lines, header first.
    public static func records(_ text: String) throws -> [CSVRecord] {
        var body = Substring(text)
        if body.first == "\u{FEFF}" {
            body = body.dropFirst()
        }
        let separator = detectSeparator(body)
        var records: [CSVRecord] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var recordLine = 1

        func finishRecord() throws {
            row.append(field)
            field = ""
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                records.append(CSVRecord(line: recordLine, fields: row))
                guard records.count <= maximumRows + 1 else { throw Failure.tooManyRows(maximumRows) }
            }
            row = []
        }

        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            let next = body.index(after: index)
            if inQuotes {
                if character == "\"" {
                    if next < body.endIndex, body[next] == "\"" {
                        field.append("\"")
                        index = body.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    if character.isNewline {
                        line += 1
                    }
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character.isNewline {
                // "\r\n" is one Character in Swift, so CRLF ends one record.
                try finishRecord()
                line += 1
                recordLine = line
            } else {
                field.append(character)
            }
            index = next
        }
        guard !inQuotes else { throw Failure.unterminatedQuote(line: line) }
        try finishRecord()
        guard !records.isEmpty else { throw Failure.empty }
        return records
    }

    static func detectSeparator(_ text: Substring) -> Character {
        let header = text.prefix { !$0.isNewline }
        let commas = header.filter { $0 == "," }.count
        let semicolons = header.filter { $0 == ";" }.count
        return semicolons > commas ? ";" : ","
    }

    /// The header this app's own CSV export writes; such a file is refused for import (it carries types, statuses
    /// and transfers the importer would misread). Restoring a backup is the way to move data between devices.
    public static func isHouseholdHubExport(header: [String]) -> Bool {
        header.map { $0.trimmingCharacters(in: .whitespaces) } == TransactionCSV.header
    }
}

/// What a CSV column holds (Sprint 15 decision 2). Everything goes to one chosen account (decision 5).
public enum CSVColumnRole: String, CaseIterable, Sendable {
    case date
    case amount
    case description
    case category
}

/// How dates in the file are written.
public enum CSVDateFormat: String, CaseIterable, Sendable {
    /// 2026-09-25 (also 2026/09/25)
    case yearMonthDay
    /// 09/25/2026
    case monthDayYear
    /// 25/09/2026
    case dayMonthYear

    /// Reads a date as a calendar day (noon local, so no zone shift moves it). Two-digit years: 00–69 are 20xx,
    /// 70–99 are 19xx. Anything after the date (a time) is ignored.
    public func date(from text: String, calendar: HouseholdCalendar) -> Date? {
        let head = text.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace && $0 != "T" }
        let parts = head.split(whereSeparator: { "-/.".contains($0) }).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        let (year, month, day): (Int, Int, Int)
        switch self {
        case .yearMonthDay: (year, month, day) = (numbers[0], numbers[1], numbers[2])
        case .monthDayYear: (year, month, day) = (numbers[2], numbers[0], numbers[1])
        case .dayMonthYear: (year, month, day) = (numbers[2], numbers[1], numbers[0])
        }
        let fullYear = year < 100 ? (year < 70 ? 2000 + year : 1900 + year) : year
        guard (1900...2200).contains(fullYear), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: fullYear, month: month, day: day, hour: 12)
        guard let date = calendar.calendar.date(from: components),
            calendar.calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }

    /// The formats every non-empty value reads as. One entry means the file decides it; several mean the user picks.
    public static func candidates(for values: [String], calendar: HouseholdCalendar) -> [CSVDateFormat] {
        let samples = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !samples.isEmpty else { return allCases }
        return allCases.filter { format in samples.allSatisfy { format.date(from: $0, calendar: calendar) != nil } }
    }
}

/// Which column plays which role, and how to read it.
public struct CSVMapping: Equatable, Sendable {
    public var columns: [CSVColumnRole: Int]
    public var dateFormat: CSVDateFormat
    /// "." or ","; the other one groups thousands.
    public var decimalMark: Character
    /// On for banks that export spending as positive numbers (decision 3).
    public var spendingIsPositive: Bool

    public init(
        columns: [CSVColumnRole: Int], dateFormat: CSVDateFormat, decimalMark: Character = ".",
        spendingIsPositive: Bool = false
    ) {
        self.columns = columns
        self.dateFormat = dateFormat
        self.decimalMark = decimalMark
        self.spendingIsPositive = spendingIsPositive
    }

    /// Guesses roles from header names (English and Spanish), leaving unknown ones unset.
    public static func guessColumns(header: [String]) -> [CSVColumnRole: Int] {
        let names: [CSVColumnRole: [String]] = [
            .date: ["date", "fecha", "posted", "transaction date", "posting date"],
            .amount: ["amount", "monto", "importe", "value", "valor", "cantidad"],
            .description: ["description", "descripcion", "memo", "payee", "concepto", "details", "name", "detalle"],
            .category: ["category", "categoria"],
        ]
        var result: [CSVColumnRole: Int] = [:]
        let folded = header.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        for role in CSVColumnRole.allCases {
            let wanted = names[role] ?? []
            // An exact name wins over one that merely contains it ("Date" over "Value date").
            if let exact = folded.firstIndex(where: { wanted.contains($0) }), !result.values.contains(exact) {
                result[role] = exact
            } else if let loose = folded.indices.first(where: { index in
                !result.values.contains(index) && wanted.contains { folded[index].contains($0) }
            }) {
                result[role] = loose
            }
        }
        return result
    }
}

/// Reads amounts strictly (Sprint 15 data-safety review): anything that could be misread is refused and shown as
/// skipped, never guessed. Accepted: one sign marker ("-12.50", "12.50-", "(12.50)", "+12.50", "12.50 DR" for a
/// debit, "12.50 CR" for a credit), the household currency's code or symbol, thousands grouped in threes with the
/// other mark ("1,234.56" or "1.234,56"), and no more decimals than the currency has (extra zeros are fine).
public enum CSVAmount {
    /// The signed value in minor units, or nil when the text isn't an amount this can read without guessing.
    public static func signedMinorUnits(_ text: String, currency: Currency, decimalMark: Character) -> Int64? {
        guard decimalMark == "." || decimalMark == "," else { return nil }
        var value = text.uppercased().filter { !$0.isWhitespace }
        var markers = 0
        var negative = false
        // Letters: only DR / CR (at the end) and the household code (anywhere) are allowed.
        if value.hasSuffix("DR") || value.hasSuffix("CR") {
            negative = value.hasSuffix("DR")
            markers += 1
            value.removeLast(2)
        }
        value = value.replacingOccurrences(of: currency.code.uppercased(), with: "")
        // A symbol prefixed with the code's country letters ("CA$", "US$") only for the household currency.
        let country = String(currency.code.uppercased().prefix(2))
        value = value.replacingOccurrences(of: country + "$", with: "$")
        guard !value.contains(where: \.isLetter) else { return nil }
        value = value.filter { !"$€£¥".contains($0) }
        if value.hasPrefix("(") && value.hasSuffix(")") {
            negative = true
            markers += 1
            value = String(value.dropFirst().dropLast())
        }
        if value.hasSuffix("-") {
            negative = true
            markers += 1
            value.removeLast()
        }
        if value.hasPrefix("-") {
            negative = true
            markers += 1
            value.removeFirst()
        } else if value.hasPrefix("+") {
            markers += 1
            value.removeFirst()
        }
        guard markers <= 1, let magnitude = minorUnits(value, currency: currency, decimalMark: decimalMark) else {
            return nil
        }
        return negative ? -magnitude : magnitude
    }

    /// Digits with at most one decimal mark, thousands groups of exactly three.
    static func minorUnits(_ text: String, currency: Currency, decimalMark: Character) -> Int64? {
        let groupMark: Character = decimalMark == "." ? "," : "."
        guard !text.isEmpty, text.allSatisfy({ $0.isASCIIDigit || $0 == decimalMark || $0 == groupMark }) else {
            return nil
        }
        let halves = text.split(separator: decimalMark, omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }
        let whole = halves[0]
        let fraction = halves.count == 2 ? halves[1] : ""
        guard !whole.isEmpty, fraction.allSatisfy(\.isASCIIDigit), !(halves.count == 2 && fraction.isEmpty) else {
            return nil
        }
        let groups = whole.split(separator: groupMark, omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) || groups.count == 1,
            groups.dropFirst().allSatisfy({ $0.count == 3 }), groups.allSatisfy({ !$0.isEmpty })
        else { return nil }
        let digits = currency.minorUnitDigits
        // More decimals than the currency has are refused unless they are zeros ("12.500" for CAD is 12.50).
        guard fraction.dropFirst(digits).allSatisfy({ $0 == "0" }) else { return nil }
        let kept = String(fraction.prefix(digits)).padding(toLength: digits, withPad: "0", startingAt: 0)
        let joined = groups.joined() + kept
        guard joined.count <= 18, let value = Int64(joined) else { return nil }
        return value
    }

    /// The decimal mark the column's values show: a mark followed by one or two digits at the end, or the last of
    /// two different marks. nil when the values don't say (then the user picks).
    public static func detectDecimalMark(_ values: [String]) -> Character? {
        var votes: Set<Character> = []
        for value in values {
            let marks = value.filter { $0 == "." || $0 == "," }
            guard let last = value.lastIndex(where: { $0 == "." || $0 == "," }) else { continue }
            let after = value[value.index(after: last)...].prefix { $0.isASCIIDigit }
            if Set(marks).count == 2 || (1...2).contains(after.count) {
                votes.insert(value[last])
            }
        }
        return votes.count == 1 ? votes.first : nil
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
