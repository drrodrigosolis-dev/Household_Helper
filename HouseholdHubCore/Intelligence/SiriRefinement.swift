import Foundation

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
/// future; the category must be an existing one allowed for the type; the merchant must use the sentence's own words.
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
        if let model, !normalized.isEmpty {
            let guess = await withTimeout(timeout) { try? await model.wishlist(normalized) }
            if let guess, let draft = validWishlist(guess, note: normalized, currency: currency) {
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
        // A sign or income word in the sentence wins; otherwise the model's kind, and only these two.
        let type: TransactionType
        switch guess.kind.trimmingCharacters(in: .whitespaces).lowercased() {
        case "income": type = .income
        case "expense", "": type = parsed.type
        default: return nil
        }
        let finalType = parsed.type == .income ? TransactionType.income : type
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
            }
        }
        guard occurredAt <= now else { return nil }
        let merchant = QuickAddSuggestionValidator.description(guess.merchant, note: note) ?? parsed.description
        var draft = TransactionDraft.quickAdd(
            amount: amount, type: finalType, occurredAt: occurredAt, categoryID: categoryID, description: merchant,
            isAIClassified: categoryID != nil, accountID: nil)
        draft.source = .shortcut
        return draft
    }

    static func validWishlist(_ guess: SiriWishlistGuess, note: String, currency: Currency) -> WishlistEntryDraft? {
        guard let name = spokenName(guess.name, note: note) else { return nil }
        let priceText = guess.price.trimmingCharacters(in: .whitespaces)
        if priceText.isEmpty {
            return WishlistEntryDraft(name: name, price: nil)
        }
        guard let price = spokenAmount(priceText, note: note, currency: currency) else { return nil }
        return WishlistEntryDraft(name: name, price: price)
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

    /// A single short line that shares a word with the note (digits allowed: "iPhone 17"), with no hidden characters.
    static func spokenName(_ proposed: String, note: String) -> String? {
        let text = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxNameLength, !text.contains(where: \.isNewline),
            !text.unicodeScalars.contains(where: { [.control, .format].contains($0.properties.generalCategory) })
        else { return nil }
        func words(_ string: String) -> Set<String> {
            Set(
                QuickAddParser.fold(string).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                    .filter { $0.count >= 2 })
        }
        return words(text).isDisjoint(with: words(note)) ? nil : text
    }

    /// `work`'s result, or nil once `duration` passes. The losing child is cancelled; `LanguageModelSession` stops
    /// generating when its task is cancelled.
    static func withTimeout<T: Sendable>(
        _ duration: Duration, _ work: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
