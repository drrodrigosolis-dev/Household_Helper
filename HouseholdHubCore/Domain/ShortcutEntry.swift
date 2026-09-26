import Foundation

/// Why a Shortcuts entry can't be recorded. Nothing is saved in either case.
public enum ShortcutEntryError: Error, Equatable, Sendable {
    /// Onboarding isn't finished, so there is no household currency yet.
    case notSetUp
    /// The text had no positive amount in the §25 grammar.
    case noAmount
}

/// Turns text typed into the Log Transaction shortcut into a draft, with the §25 parser only (never a model). The
/// intent shows the draft for confirmation and saves it only after the person agrees (Sprint 8 default 6).
public enum ShortcutEntry {
    public static func draft(
        text: String, settings: SettingsSnapshot?, now: Date, calendar: HouseholdCalendar
    ) throws -> TransactionDraft {
        guard let settings, settings.onboardingCompleted, let currency = try? Currency(code: settings.currencyCode)
        else { throw ShortcutEntryError.notSetUp }
        // No category options: a #tag is dropped rather than guessed; the category can be set later in the app.
        let parsed = QuickAddParser(currency: currency, categories: [], calendar: calendar).parse(text, now: now)
        guard let amount = parsed.amount else { throw ShortcutEntryError.noAmount }
        return TransactionDraft(
            amount: amount, type: parsed.type, occurredAt: parsed.occurredAt,
            notes: parsed.description.isEmpty ? nil : parsed.description, source: .shortcut)
    }
}
