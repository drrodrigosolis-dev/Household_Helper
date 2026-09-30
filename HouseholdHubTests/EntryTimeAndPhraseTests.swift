import Foundation
import Testing

@testable import HouseholdHubCore

/// Owner request 2026-09-28: entry text understands a time of day (tasks, Quick Add, Siri), and Quick Add reads
/// income and expense phrases ("got paid", "I had to pay", "me pagaron", "pagué").
struct EntryTimeAndPhraseTests {
    private static let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
    /// Friday 2026-09-25 15:00 in Vancouver.
    private static let now = Date(timeIntervalSince1970: 1_790_373_600)

    private static let cad = try! Currency(code: "CAD")

    private var now: Date { Self.now }
    private var calendar: HouseholdCalendar { Self.calendar }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `minutes` after midnight, `days` from today (negative: back).
    private static func at(_ minutes: Int, days: Int) -> Date {
        let day = calendar.calendar.date(byAdding: .day, value: days, to: now)!
        return calendar.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
    }

    private static func startOfDay(_ days: Int) -> Date {
        calendar.startOfDay(for: calendar.calendar.date(byAdding: .day, value: days, to: now)!)
    }

    private var parser: QuickAddParser {
        QuickAddParser(currency: Self.cad, categories: [], calendar: calendar)
    }

    @Test func referenceInstantIsFridayAtThreeInVancouver() {
        #expect(calendar.calendar.component(.weekday, from: now) == 6)
        #expect(calendar.calendar.component(.hour, from: now) == 15)
    }

    // MARK: The time grammar

    static let englishTimeCases: [(String, Int)] = [
        ("3pm", 900), ("3 pm", 900), ("3:30pm", 930), ("3:30 p.m.", 930), ("15:30", 930), ("at 3pm", 900),
        ("at 15:30", 930), ("noon", 720), ("midnight", 0), ("12am", 0), ("12pm", 720), ("3 PM", 900),
        ("At Noon.", 720), ("at midnight", 0), ("9:05AM,", 545), ("3:30", 210), ("0:15", 15),
    ]

    @Test(arguments: englishTimeCases)
    func englishTimes(text: String, minutes: Int) {
        let tokens = Self.words(text)
        let match = TimeOfDayParser.firstMatch(in: tokens)
        #expect(match == TimeOfDayParser.Match(minutes: minutes, tokens: 0..<tokens.count))
    }

    static let spanishTimeCases: [(String, Int)] = [
        ("a las 3", 180), ("a las 15:30", 930), ("a las 3pm", 900), ("3 de la tarde", 900), ("8 de la mañana", 480),
        ("10 de la noche", 1320), ("mediodía", 720), ("medianoche", 0), ("A LAS 3", 180), ("MEDIODIA", 720),
        ("a las 3 de la tarde", 900), ("12 de la noche", 0), ("12 de la tarde", 720), ("al mediodía", 720),
        ("a medianoche", 0), ("a la 1", 60), ("a las 0", 0), ("a las 23", 1380), ("5 de la madrugada", 300),
        ("8 de la manana", 480),
    ]

    @Test(arguments: spanishTimeCases)
    func spanishTimes(text: String, minutes: Int) {
        let tokens = Self.words(text)
        let match = TimeOfDayParser.firstMatch(in: tokens)
        #expect(match == TimeOfDayParser.Match(minutes: minutes, tokens: 0..<tokens.count))
    }

    @Test(arguments: [
        "buy 3 eggs", "40 lunch", "3", "at 3", "25:00", "at 25:00", "13pm", "0pm", "3:75", "3:5pm", "a las 24",
        "a las 3:75", "15 de la tarde", "0 de la noche", "am", "p.m.", "12.30", "3.5pm", "lunch at Safeway",
    ])
    func whatIsNotATime(text: String) {
        #expect(TimeOfDayParser.firstMatch(in: Self.words(text)) == nil)
    }

    @Test func theFirstTimeWinsAndItsWordsAreFound() {
        let match = TimeOfDayParser.firstMatch(in: Self.words("call Ana at 3pm or 5pm"))
        #expect(match == TimeOfDayParser.Match(minutes: 900, tokens: 2..<4))
    }

    /// A time with no date word: today while it is still ahead of `now`, tomorrow once it has passed.
    // Minutes after midnight written out (16:00, 15:01, 15:00, 14:00, 0:00, 23:59): arithmetic inside the literal
    // was more than the type checker would solve in time (local build on ebc972d).
    @Test(arguments: [(960, 0), (901, 0), (900, 1), (840, 1), (0, 1), (1439, 0)] as [(Int, Int)])
    func aTaskTimeWithoutADayIsTheNextOne(minutes: Int, daysAhead: Int) {
        let day = TimeOfDayParser.dueDay(forMinutes: minutes, now: now, calendar: calendar)
        #expect(day == Self.startOfDay(daysAhead))
    }

    // MARK: Task lines (batch add)

    static let taskLineTimes: [(String, String, Int, Int)] = [
        ("call plumber 4pm", "call plumber", 0, 960),
        ("call plumber 2pm", "call plumber", 1, 840),
        ("call plumber 3pm", "call plumber", 1, 900),
        ("call plumber friday at 9am", "call plumber", 0, 540),
        ("dentist tomorrow at 15:30", "dentist", 1, 930),
        ("dentista mañana a las 10", "dentista", 1, 600),
        ("gym 8 de la mañana", "gym", 1, 480),
        ("cena 10 de la noche", "cena", 0, 1320),
        ("lunch noon monday", "lunch", 3, 720),
        ("pagar renta a las 3", "pagar renta", 1, 180),
        ("take out trash midnight", "take out trash", 1, 0),
        ("Buy 3 eggs at 5:30 PM", "Buy 3 eggs", 0, 1050),
    ]

    @Test(arguments: taskLineTimes)
    func taskLinesReadATime(text: String, title: String, daysAhead: Int, minutes: Int) throws {
        let line = TaskLineParser(calendar: calendar).parse(text, now: now)
        #expect(line.title == title)
        #expect(line.dueDate == Self.startOfDay(daysAhead))
        #expect(line.dueTimeMinutes == minutes)
        try TaskDraft(title: line.title, dueDate: line.dueDate, dueTimeMinutes: line.dueTimeMinutes).validate()
    }

    @Test(arguments: [
        "buy 3 eggs", "3pm", "friday 3pm", "read chapter 12", "meet at 3", "fix 25:00 clock", "13pm party",
        "room 3:75",
    ])
    func taskLinesWithoutAValidTimeKeepTheirWords(text: String) {
        let line = TaskLineParser(calendar: calendar).parse(text, now: now)
        #expect(line.title == text)
        #expect(line.dueTimeMinutes == nil)
    }

    @Test func aBatchTaskCarriesItsTime() throws {
        let planner = BatchAddPlanner(kind: .tasks, currency: Self.cad, categories: [], calendar: calendar)
        let drafts = planner.plan("call plumber 4pm\nbuy 3 eggs", now: now).taskDrafts
        #expect(drafts.count == 2)
        #expect(drafts.first?.dueTimeMinutes == 960)
        #expect(drafts.first?.dueDate == Self.startOfDay(0))
        #expect(drafts.last?.title == "buy 3 eggs")
        #expect(drafts.last?.dueTimeMinutes == nil)
        for draft in drafts {
            try draft.validate()
        }
    }

    // MARK: Siri tasks

    static let siriTaskTimes: [(String, String, Int, Int)] = [
        ("call the plumber friday at 3pm.", "call the plumber", 0, 900),
        ("Llamar al fontanero a las 5 de la tarde", "Llamar al fontanero", 0, 1020),
        ("water plants at 7:30 am", "water plants", 1, 450),
    ]

    @Test(arguments: siriTaskTimes)
    func siriTasksReadATime(text: String, title: String, daysAhead: Int, minutes: Int) throws {
        let draft = try TaskEntry.draft(text: text, now: now, calendar: calendar)
        #expect(draft.title == title)
        #expect(draft.dueDate == Self.startOfDay(daysAhead))
        #expect(draft.dueTimeMinutes == minutes)
        try draft.validate()
    }

    // MARK: Quick Add times

    /// Text, amount in cents, description, days from today, minutes after midnight.
    static let quickAddTimes: [(String, Int64, String, Int, Int)] = [
        ("12 lunch 1pm", 1_200, "lunch", 0, 780),
        ("12 lunch 1:30 p.m.", 1_200, "lunch", 0, 810),
        ("20 dinner 8pm", 2_000, "dinner", -1, 1200),
        ("20 dinner yesterday 8pm", 2_000, "dinner", -1, 1200),
        ("40 cena a las 9 de la noche ayer", 4_000, "cena", -1, 1260),
        ("3 pm 40 taxi", 4_000, "taxi", 0, 900),
        ("40 taxi a las 3", 4_000, "taxi", 0, 180),
        ("9 coffee at noon monday", 900, "coffee", -4, 720),
        ("I paid 40 at 11am for gas", 4_000, "gas", 0, 660),
    ]

    @Test(arguments: quickAddTimes)
    func quickAddReadsATime(text: String, minorUnits: Int64, description: String, days: Int, minutes: Int) {
        let parsed = parser.parse(text, now: now)
        #expect(parsed.amount == Money(minorUnits: minorUnits, currencyCode: "CAD"))
        #expect(parsed.description == description)
        #expect(parsed.occurredAt == Self.at(minutes, days: days))
        #expect(parsed.timeOfDayMinutes == minutes)
        #expect(parsed.dateRecognized)
        #expect(parsed.occurredAt <= now)
    }

    @Test func aLaterTimeOnANamedTodayIsNow() {
        let parsed = parser.parse("5 coffee today 5pm", now: now)
        #expect(parsed.occurredAt == now)
        #expect(parsed.description == "coffee")
    }

    static let quickAddNonTimes: [(String, Int64, String)] = [
        ("buy 3 eggs", Int64(300), "buy eggs"), ("40 room 25:00", 4_000, "room 25:00"),
        ("40 at 3 guys", 4_000, "at 3 guys"),
    ]

    @Test(arguments: quickAddNonTimes)
    func quickAddLeavesWhatIsNotATime(text: String, minorUnits: Int64, description: String) {
        let parsed = parser.parse(text, now: now)
        #expect(parsed.amount == Money(minorUnits: minorUnits, currencyCode: "CAD"))
        #expect(parsed.description == description)
        #expect(parsed.occurredAt == now)
        #expect(parsed.timeOfDayMinutes == nil)
    }

    @Test func aShortcutEntryKeepsTheTime() throws {
        let settings = SiriEntryTests.settings()
        let draft = try ShortcutEntry.draft(text: "18 lunch 12:30", settings: settings, now: now, calendar: calendar)
        #expect(draft.occurredAt == Self.at(750, days: 0))
        #expect(draft.merchantName == "lunch")
    }

    @Test func aSpokenTimeStaysOnTheDayTheModelPicked() async throws {
        let model = FakeSiriModel(
            transactionGuess: SiriTransactionGuess(
                amount: "40", kind: "expense", merchant: "", datePhrase: "wednesday", category: ""))
        // The grammar reads the first day word (Monday); the model picks Wednesday, and the 3pm goes with it.
        let refined = try await SiriRefinement.transaction(
            text: "paid 40 monday for dinner wednesday at 3pm", settings: SiriEntryTests.settings(), categories: [],
            model: model, now: now, calendar: calendar)
        #expect(refined.fromModel)
        #expect(refined.draft.occurredAt == Self.at(900, days: -2))
    }

    // MARK: Income and expense phrases

    static let englishPhrases: [(String, Int64, TransactionType, String)] = [
        ("got paid 1200", 120_000, .income, ""),
        ("I got paid 1200 salary", 120_000, .income, "salary"),
        ("I received 50 from mom", 5_000, .income, "from mom"),
        ("I earned 300 tutoring", 30_000, .income, "tutoring"),
        ("earned 300 tutoring", 30_000, .income, "tutoring"),
        ("I was paid 900 by Acme", 90_000, .income, "by Acme"),
        ("income 100 bonus", 10_000, .income, "bonus"),
        ("I paid 40 for gas", 4_000, .expense, "gas"),
        ("paid for gas 40", 4_000, .expense, "gas"),
        ("gas paid for 40", 4_000, .expense, "gas"),
        ("I had to pay 80 dentist", 8_000, .expense, "dentist"),
        ("had to pay 80 dentist", 8_000, .expense, "dentist"),
        ("it was worth 30 lunch", 3_000, .expense, "lunch"),
        ("was worth 30 lunch", 3_000, .expense, "lunch"),
        ("I spent 25 on books", 2_500, .expense, "on books"),
        ("it cost 15 parking", 1_500, .expense, "parking"),
        ("cost 15 parking", 1_500, .expense, "parking"),
        ("I bought 9 flowers", 900, .expense, "flowers"),
        ("bought 9 flowers", 900, .expense, "flowers"),
        ("Paid, 12 taxi", 1_200, .expense, "taxi"),
        ("+20 paid back", 2_000, .income, "paid back"),
        ("+ 20 I paid it forward", 2_000, .income, "I paid it forward"),
        ("got paid 100 but paid 20 fee", 10_000, .income, "but paid 20 fee"),
        ("paid 20 then got paid 100", 2_000, .expense, "then got paid 100"),
        ("prepaid 30 card", 3_000, .expense, "prepaid card"),
        ("got 2 tickets 50", 200, .expense, "got tickets 50"),
    ]

    @Test(arguments: englishPhrases)
    func englishTypePhrases(text: String, minorUnits: Int64, type: TransactionType, description: String) {
        let parsed = parser.parse(text, now: now)
        #expect(parsed.amount == Money(minorUnits: minorUnits, currencyCode: "CAD"))
        #expect(parsed.type == type)
        #expect(parsed.description == description)
    }

    static let spanishPhrases: [(String, Int64, TransactionType, String)] = [
        ("me pagaron 500 sueldo", 50_000, .income, "sueldo"),
        ("Me Pagaron 500 sueldo", 50_000, .income, "sueldo"),
        ("cobré 300 consulta", 30_000, .income, "consulta"),
        ("cobre 300 consulta", 30_000, .income, "consulta"),
        ("recibí 50 regalo", 5_000, .income, "regalo"),
        ("recibido 50 regalo", 5_000, .income, "regalo"),
        ("gané 200 rifa", 20_000, .income, "rifa"),
        ("ingreso 1200 salario", 120_000, .income, "salario"),
        ("me depositaron 1000 quincena", 100_000, .income, "quincena"),
        ("tuve que pagar 80 dentista", 8_000, .expense, "dentista"),
        ("pagué 40 por gasolina", 4_000, .expense, "gasolina"),
        ("PAGUE 40 gasolina", 4_000, .expense, "gasolina"),
        ("gasté 25 libros", 2_500, .expense, "libros"),
        ("gaste 25 libros", 2_500, .expense, "libros"),
        ("costó 15 estacionamiento", 1_500, .expense, "estacionamiento"),
        ("compré 9 flores", 900, .expense, "flores"),
        ("gasto 12 taxi", 1_200, .expense, "taxi"),
        ("pagué 40 y me pagaron 100", 4_000, .expense, "y me pagaron 100"),
    ]

    @Test(arguments: spanishPhrases)
    func spanishTypePhrases(text: String, minorUnits: Int64, type: TransactionType, description: String) {
        let parsed = parser.parse(text, now: now)
        #expect(parsed.amount == Money(minorUnits: minorUnits, currencyCode: "CAD"))
        #expect(parsed.type == type)
        #expect(parsed.description == description)
    }

    @Test(arguments: [("got paid 1200", TransactionType.income), ("tuve que pagar 80 dentista", .expense)])
    func shortcutsReadThePhrases(text: String, type: TransactionType) throws {
        let settings = SiriEntryTests.settings()
        let draft = try ShortcutEntry.draft(text: text, settings: settings, now: now, calendar: calendar)
        #expect(draft.type == type)
    }

    @Test func anEmptyDescriptionNamesNoMerchant() throws {
        let draft = try ShortcutEntry.draft(
            text: "got paid 1200", settings: SiriEntryTests.settings(), now: now, calendar: calendar)
        #expect(draft.type == .income)
        #expect(draft.merchantName == nil)
    }
}
