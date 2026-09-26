import AppIntents
import HouseholdHubCore

/// Opens Quick Add from Shortcuts or Siri (spec §24.4). The widget itself uses a link, not this intent.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add"
    static let description: IntentDescription? = IntentDescription("Opens Household Hub's Quick Add.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.isQuickAddPresented = true
        return .result()
    }
}

/// Records a transaction typed in the Quick Add grammar ("47.50 coffee", "+ 1200 paycheck yesterday"). The §25
/// parser reads it (never the on-device model), and nothing is saved until the person confirms what was understood
/// (Sprint 8 default 6).
struct LogTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Transaction"
    static let description: IntentDescription? = IntentDescription(
        "Records an expense or income written like Quick Add, for example “47.50 coffee”.")
    static let supportedModes: IntentModes = .background
    /// Never from the Lock Screen: recording money needs an unlocked device (and an unlocked store).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Entry", requestValueDialog: "What should be recorded? For example, 47.50 coffee")
    var text: String

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case unavailable
        case notSetUp
        case noAmount

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .unavailable: "Household Hub couldn't open its data."
            case .notSetUp: "Open Household Hub and finish setting it up first."
            case .noAmount: "There was no amount in that entry. Try something like “47.50 coffee”."
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let services = await SharedServices.current else { throw Failure.unavailable }
        guard let settings = try await services.transactions.settingsSnapshot(), settings.onboardingCompleted,
            let currency = try? Currency(code: settings.currencyCode)
        else { throw Failure.notSetUp }
        let now = Date.now
        let calendar = HouseholdCalendar(timeZone: .current)
        // No category options: a #tag is dropped rather than guessed; the category can be set later in the app.
        let parsed = QuickAddParser(currency: currency, categories: [], calendar: calendar).parse(text, now: now)
        guard let amount = parsed.amount else { throw Failure.noAmount }
        let kind = parsed.type == .income ? String(localized: "income") : String(localized: "expense")
        let day = parsed.occurredAt.formatted(date: .abbreviated, time: .omitted)
        try await requestConfirmation(
            actionName: .log, dialog: "Record \(amount.formatted()) \(kind) on \(day)?")
        let draft = TransactionDraft(
            amount: amount, type: parsed.type, occurredAt: parsed.occurredAt,
            notes: parsed.description.isEmpty ? nil : parsed.description, source: .widget)
        try await services.transactions.create(draft, now: now)
        await WidgetSync.refresh(services)
        return .result(dialog: "Recorded \(amount.formatted()) \(kind).")
    }
}

struct HouseholdHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickAddIntent(), phrases: ["Quick Add in \(.applicationName)"], shortTitle: "Quick Add",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: LogTransactionIntent(), phrases: ["Log a transaction in \(.applicationName)"],
            shortTitle: "Log Transaction", systemImageName: "square.and.pencil")
    }
}
