import Foundation
import Synchronization

/// What the on-device model proposed for a spoken transaction (Sprint 25). Every field is raw text the validator
/// decides on; an empty string means "not said".
public struct SiriTransactionGuess: Equatable, Sendable {
    /// The amount exactly as the model wrote it, e.g. "40" or "9.50".
    public var amount: String
    /// "expense" or "income".
    public var kind: String
    public var merchant: String
    /// The words that name the day, copied from the sentence ("yesterday", "ayer", "monday").
    public var datePhrase: String
    /// One of the household's category names.
    public var category: String

    public init(amount: String, kind: String, merchant: String, datePhrase: String, category: String) {
        self.amount = amount
        self.kind = kind
        self.merchant = merchant
        self.datePhrase = datePhrase
        self.category = category
    }
}

/// What the on-device model proposed for a spoken wishlist item.
public struct SiriWishlistGuess: Equatable, Sendable {
    public var name: String
    /// The price exactly as the model wrote it, or empty.
    public var price: String

    public init(name: String, price: String) {
        self.name = name
        self.price = price
    }
}

/// The seam in front of `LanguageModelSession` (Sprint 25), so the validation and fallback rules are tested with a
/// fake. Implementations only turn text into guesses; they never see or write the store (§6).
public protocol SiriDraftModel: Sendable {
    func transaction(_ text: String, categoryNames: [String]) async throws -> SiriTransactionGuess
    func wishlist(_ text: String) async throws -> SiriWishlistGuess
}

/// A draft for the intent's confirmation and whether the on-device model shaped it.
public struct RefinedDraft<Draft: Equatable & Sendable>: Equatable, Sendable {
    public var draft: Draft
    public var fromModel: Bool

    public init(draft: Draft, fromModel: Bool) {
        self.draft = draft
        self.fromModel = fromModel
    }
}

/// Owner answer 3 (Sprint 25): a spoken sentence goes to the on-device model first where Apple Intelligence is
/// available; its answer is checked with the grammar's own rules and, when anything is missing, wrong, late or
/// throws, the deterministic grammar's draft is used instead. Either way the result is only a draft: the intent shows
/// it in `requestConfirmation` and nothing is saved without a yes (§6, §12).
///
/// Validation: the amount must be positive, in the household currency with no extra decimals, and one of the
/// numbers the person actually said (the model may choose between them, never invent one); the date comes from the
/// §25 day words in the sentence (the model may pick which), so it is today or up to six days back, never in the
/// future; the type is always the grammar's (§25.2); the category must be an existing one allowed for the type; every
/// word of the merchant or wishlist name must be one of the sentence's own; a wishlist price must be the grammar's.
public enum SiriRefinement {
    /// The model's answer is abandoned after this long and the grammar's draft is used.
    public static let modelTimeout: Duration = .seconds(6)

    /// A transaction draft for `text`. Throws `ShortcutEntryError` only when neither the model nor the grammar
    /// yields one. `model` is nil when the model is unavailable or its switch is off; `categories` is empty when the
    /// category switch is off.
    public static func transaction(
        text: String, settings: SettingsSnapshot?, categories: [QuickAddCategoryOption], model: (any SiriDraftModel)?,
        now: Date, calendar: HouseholdCalendar, timeout: Duration = SiriRefinement.modelTimeout
    ) async throws -> RefinedDraft<TransactionDraft> {
        guard let settings, settings.onboardingCompleted, let currency = try? Currency(code: settings.currencyCode)
        else { throw ShortcutEntryError.notSetUp }
        let normalized = SiriText.normalize(text)
        let fallback = Result {
            try ShortcutEntry.draft(text: normalized, settings: settings, now: now, calendar: calendar)
        }
        if let model, !normalized.isEmpty {
            let names = categories.map(\.name)
            let guess = await withTimeout(timeout) { try? await model.transaction(normalized, categoryNames: names) }
            if let guess,
                let draft = validTransaction(
                    guess, note: normalized, currency: currency, categories: categories, now: now, calendar: calendar)
            {
                return RefinedDraft(draft: draft, fromModel: true)
            }
        }
        return RefinedDraft(draft: try fallback.get(), fromModel: false)
    }

    /// A wishlist draft for `text`; throws `SiriEntryError` only when neither the model nor the grammar yields one.
    public static func wishlist(
        text: String, settings: SettingsSnapshot?, model: (any SiriDraftModel)?,
        timeout: Duration = SiriRefinement.modelTimeout
    ) async throws -> RefinedDraft<WishlistEntryDraft> {
        guard let settings, settings.onboardingCompleted, let currency = try? Currency(code: settings.currencyCode)
        else { throw SiriEntryError.notSetUp }
        let normalized = SiriText.normalize(text)
        let fallback = Result { try WishlistEntry.draft(text: normalized, settings: settings) }
        // The model is asked only when the grammar reads the sentence, so its price is checked against the grammar's.
        if let model, case .success(let grammar) = fallback {
            let guess = await withTimeout(timeout) { try? await model.wishlist(normalized) }
            if let guess, let draft = validWishlist(guess, note: normalized, grammar: grammar, currency: currency) {
                return RefinedDraft(draft: draft, fromModel: true)
            }
        }
        return RefinedDraft(draft: try fallback.get(), fromModel: false)
    }

    // MARK: Validation

    static func validTransaction(
        _ guess: SiriTransactionGuess, note: String, currency: Currency, categories: [QuickAddCategoryOption],
        now: Date, calendar: HouseholdCalendar
    ) -> TransactionDraft? {
        guard let amount = spokenAmount(guess.amount, note: note, currency: currency) else { return nil }
        let parser = QuickAddParser(currency: currency, categories: [], calendar: calendar)
        let parsed = parser.parse(note, now: now)
        // The type always comes from the §25.2 grammar: income only with a leading "+" or an income phrase ("got
        // paid", "received", "me pagaron", "ingreso"), expense otherwise ("I paid", "gasto" included). The model can't
        // turn an expense into income or income into an expense; an answer that isn't one of the two kinds is refused
        // outright.
        guard ["income", "expense", ""].contains(guess.kind.trimmingCharacters(in: .whitespaces).lowercased()) else {
            return nil
        }
        let finalType = parsed.type
        let categoryName = guess.category.trimmingCharacters(in: .whitespaces)
        var categoryID: UUID?
        if !categoryName.isEmpty {
            categoryID =
                categories.first {
                    $0.name.caseInsensitiveCompare(categoryName) == .orderedSame && $0.kind.allows(finalType)
                }?.id
        }
        // The day is read from the model's phrase by the §25 day words, never from a date the model computed, and
        // only when the phrase is the sentence's own words: the model may choose between days the person named
        // ("paid monday for wednesday's dinner"), never add one.
        var occurredAt = parsed.occurredAt
        let phrase = SiriText.normalize(guess.datePhrase)
        if !phrase.isEmpty {
            let spoken = Set(note.split(separator: " ").map { QuickAddParser.fold(String($0)) })
            let fromNote = phrase.split(separator: " ").allSatisfy { spoken.contains(QuickAddParser.fold(String($0))) }
            let day = parser.parse(phrase, now: now)
            if fromNote, day.dateRecognized {
                occurredAt = day.occurredAt
                // A time the sentence named stays on the day the model picked ("paid monday at 3pm").
                if day.timeOfDayMinutes == nil, let minutes = parsed.timeOfDayMinutes {
                    occurredAt = TimeOfDayParser.pastInstant(
                        minutes: minutes, onDayOf: day.occurredAt, dayNamed: true, now: now, calendar: calendar)
                }
            }
        }
        guard occurredAt <= now else { return nil }
        let merchant = spokenMerchant(guess.merchant, note: note) ?? parsed.description
        var draft = TransactionDraft.quickAdd(
            amount: amount, type: finalType, occurredAt: occurredAt, categoryID: categoryID, description: merchant,
            isAIClassified: categoryID != nil, accountID: nil)
        draft.source = .shortcut
        return draft
    }

    /// The model's wishlist answer checked against the grammar's own reading of the sentence (`grammar`).
    ///
    /// Price rule (the stricter of the two considered): only the grammar's "for/por <amount>" is ever a price. When
    /// the grammar found one, the model may repeat it or leave the price empty, and the grammar's price is kept either
    /// way; any other amount refuses the answer. When the grammar found none, a model price refuses the answer, so a
    /// number in the name ("a new iPhone 17") is never read as a price and the grammar keeps it in the name.
    static func validWishlist(
        _ guess: SiriWishlistGuess, note: String, grammar: WishlistEntryDraft, currency: Currency
    ) -> WishlistEntryDraft? {
        guard let name = spokenName(guess.name, note: note) else { return nil }
        let priceText = guess.price.trimmingCharacters(in: .whitespaces)
        if priceText.isEmpty {
            return WishlistEntryDraft(name: name, price: grammar.price)
        }
        guard let said = grammar.price, spokenAmount(priceText, note: note, currency: currency) == said else {
            return nil
        }
        return WishlistEntryDraft(name: name, price: said)
    }

    /// A positive amount in the §25 grammar that is one of the numbers written in `note`, within the plan limit and
    /// with no more decimals than the currency has.
    static func spokenAmount(_ text: String, note: String, currency: Currency) -> Money? {
        guard let value = QuickAddParser.plainAmount(SiriText.normalize(text)),
            SiriText.writtenAmounts(in: note).contains(value),
            let money = try? WishlistEntry.validPrice(value, currency: currency)
        else { return nil }
        return money
    }

    static let maxNameLength = 80

    /// A single short line with no hidden characters whose every word of two or more letters or digits, after case
    /// and diacritic folding, is one of the sentence's own words ("iPhone 17" from "a new iPhone 17"). A word the
    /// person didn't say ("Sony" added to "headphones for 149") refuses the name.
    static func spokenName(_ proposed: String, note: String) -> String? {
        let text = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxNameLength, !text.contains(where: \.isNewline),
            !text.unicodeScalars.contains(where: { [.control, .format].contains($0.properties.generalCategory) })
        else { return nil }
        let proposedWords = spokenWords(text)
        guard !proposedWords.isEmpty, proposedWords.isSubset(of: spokenWords(note)) else { return nil }
        return text
    }

    /// The Quick Add description rules (no digits, no number words, no hidden characters) plus the name rule above:
    /// every word of the merchant is one the person said.
    static func spokenMerchant(_ proposed: String, note: String) -> String? {
        guard let text = QuickAddSuggestionValidator.description(proposed, note: note),
            spokenName(text, note: note) != nil
        else { return nil }
        return text
    }

    /// Folded words of two or more letters or digits.
    static func spokenWords(_ text: String) -> Set<String> {
        Set(
            QuickAddParser.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                .filter { $0.count >= 2 })
    }

    /// `work`'s result, or nil once `duration` passes, even when `work` ignores cancellation: it runs in an
    /// unstructured task raced against a timer, and whichever finishes first resumes the caller, exactly once. At the
    /// timeout the work is cancelled (`LanguageModelSession` stops generating then) and a later answer is dropped.
    /// Cancelling the caller also returns nil at once.
    static func withTimeout<T: Sendable>(
        _ duration: Duration, _ work: @escaping @Sendable () async -> T?
    ) async -> T? {
        let answer = FirstAnswer<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                answer.arm(continuation)
                let worker = Task {
                    let value = await work()
                    answer.resume(value)
                }
                Task {
                    try? await Task.sleep(for: duration)
                    answer.resume(nil)
                    worker.cancel()
                }
            }
        } onCancel: {
            answer.resume(nil)
        }
    }
}

/// Resumes one continuation with the first answer it is given and drops every later one (`SiriRefinement`'s
/// timeout). An answer given before the continuation is armed is kept and delivered when it is.
final class FirstAnswer<T: Sendable>: Sendable {
    private enum Phase: Sendable {
        case pending
        case armed(CheckedContinuation<T?, Never>)
        case answered(T?)
        case resumed
    }

    private let phase = Mutex<Phase>(.pending)

    func arm(_ continuation: CheckedContinuation<T?, Never>) {
        let early: T?? = phase.withLock { current in
            if case .answered(let value) = current {
                current = .resumed
                return .some(value)
            }
            current = .armed(continuation)
            return .none
        }
        if let early {
            continuation.resume(returning: early)
        }
    }

    func resume(_ value: T?) {
        let waiting: CheckedContinuation<T?, Never>? = phase.withLock { current in
            switch current {
            case .pending:
                current = .answered(value)
                return nil
            case .armed(let continuation):
                current = .resumed
                return continuation
            case .answered, .resumed:
                return nil
            }
        }
        waiting?.resume(returning: value)
    }
}
