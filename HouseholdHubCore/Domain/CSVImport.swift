import Foundation

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
    }

    /// Rows of fields, header first. Blank lines are dropped.
    public static func parse(_ text: String) throws -> [[String]] {
        guard text.utf8.count <= maximumBytes else { throw Failure.tooLarge }
        var body = Substring(text)
        if body.first == "\u{FEFF}" {
            body = body.dropFirst()
        }
        let separator = detectSeparator(body)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
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
                    if character.isNewline { line += 1 }
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character.isNewline {
                // "\r\n" is one Character in Swift, so CRLF ends one row.
                row.append(field)
                field = ""
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    rows.append(row)
                    guard rows.count <= maximumRows + 1 else { throw Failure.tooManyRows(maximumRows) }
                }
                row = []
                line += 1
            } else {
                field.append(character)
            }
            index = next
        }
        guard !inQuotes else { throw Failure.unterminatedQuote(line: line) }
        row.append(field)
        if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            rows.append(row)
        }
        guard rows.count <= maximumRows + 1 else { throw Failure.tooManyRows(maximumRows) }
        guard !rows.isEmpty else { throw Failure.empty }
        return rows
    }

    static func detectSeparator(_ text: Substring) -> Character {
        let header = text.prefix { !$0.isNewline }
        let commas = header.filter { $0 == "," }.count
        let semicolons = header.filter { $0 == ";" }.count
        return semicolons > commas ? ";" : ","
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

    /// Reads a date as a calendar day (noon local, so no zone shift moves it). Two-digit years are 20xx.
    public func date(from text: String, calendar: HouseholdCalendar) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { "-/.".contains($0) }).map(String.init)
        // Anything after the date (a time) is ignored.
        guard parts.count >= 3 else { return nil }
        let numbers = parts.prefix(3).map { Int($0.prefix { $0.isNumber }) }
        guard let first = numbers[0], let second = numbers[1], let third = numbers[2] else { return nil }
        let (year, month, day): (Int, Int, Int)
        switch self {
        case .yearMonthDay: (year, month, day) = (first, second, third)
        case .monthDayYear: (year, month, day) = (third, first, second)
        case .dayMonthYear: (year, month, day) = (third, second, first)
        }
        let fullYear = year < 100 ? 2000 + year : year
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
    /// On for banks that export spending as positive numbers (decision 3).
    public var spendingIsPositive: Bool

    public init(columns: [CSVColumnRole: Int], dateFormat: CSVDateFormat, spendingIsPositive: Bool = false) {
        self.columns = columns
        self.dateFormat = dateFormat
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

/// Reads amounts as written by banks: "-12.50", "12.50-", "(12.50)", "$1,234.56", "1.234,56", "1 234,56".
public enum CSVAmount {
    /// The signed value in minor units, or nil when it isn't a number.
    public static func signedMinorUnits(_ text: String, currency: Currency) -> Int64? {
        // Currency symbols, codes and spaces go first, so "CA$ -7" reads like "-7".
        var value = text.filter { !$0.isWhitespace && !$0.isLetter && !"$€£¥".contains($0) }
        var negative = false
        if value.hasPrefix("(") && value.hasSuffix(")") {
            negative = true
            value = String(value.dropFirst().dropLast())
        }
        if value.hasSuffix("-") {
            negative.toggle()
            value = String(value.dropLast())
        }
        if value.hasPrefix("-") {
            negative.toggle()
            value = String(value.dropFirst())
        } else if value.hasPrefix("+") {
            value = String(value.dropFirst())
        }
        // What is left must be digits and single separators between digits.
        let kept = value
        guard kept.first?.isNumber == true, kept.last?.isNumber == true,
            kept.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }),
            !zip(kept, kept.dropFirst()).contains(where: { !$0.isNumber && !$1.isNumber })
        else { return nil }
        let normalized = normalizeSeparators(kept)
        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
            let money = try? Money(decimal: decimal, currency: currency)
        else { return nil }
        return negative ? -money.minorUnits : money.minorUnits
    }

    /// The last separator is the decimal point when one or two digits follow it, or three after a lone "."
    /// ("12.500"); otherwise every separator groups digits ("1,234" and "1.234.567" are whole numbers).
    static func normalizeSeparators(_ text: String) -> String {
        guard let last = text.lastIndex(where: { $0 == "." || $0 == "," }) else { return text }
        let fraction = text[text.index(after: last)...]
        let separators = text.filter { $0 == "." || $0 == "," }.count
        let isDecimal =
            (1...2).contains(fraction.count) || (fraction.count == 3 && text[last] == "." && separators == 1)
        let whole = text[..<last].filter(\.isNumber)
        return isDecimal ? whole + "." + fraction : text.filter(\.isNumber)
    }
}
