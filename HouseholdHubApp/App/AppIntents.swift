import AppIntents
import HouseholdHubCore

/// Opens Quick Add from Shortcuts or Siri (spec §24.4). The widget itself uses a link, not this intent.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add"
    static let description: IntentDescription? = IntentDescription("Opens Household Hub's Quick Add.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        if !AppRouter.shared.isOnboarding {
            AppRouter.shared.isQuickAddPresented = true
        }
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
        case locked

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .unavailable: "Household Hub couldn't open its data."
            case .notSetUp: "Open Household Hub and finish setting it up first."
            case .noAmount: "There was no amount in that entry. Try something like “47.50 coffee”."
            case .locked: "Household Hub is locked. Unlock it to record a transaction."
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let services = await SharedServices.current, !(await AppRouter.shared.isRestoring) else {
            throw Failure.unavailable
        }
        // The app's own lock applies here too; otherwise the shortcut would be a way around it.
        // With no device passcode nothing can authenticate, and the app itself opens then too (see AppRootView).
        if try await services.transactions.isLockEnabled(), BiometricGate.isAvailable {
            let reason = String(localized: "Unlock Household Hub to record a transaction.")
            guard await BiometricGate.authenticate(reason: reason) else { throw Failure.locked }
        }
        let now = Date.now
        let calendar = HouseholdCalendar(timeZone: .current)
        let draft: TransactionDraft
        do {
            draft = try ShortcutEntry.draft(
                text: text, settings: try await services.transactions.settingsSnapshot(), now: now, calendar: calendar)
        } catch ShortcutEntryError.notSetUp {
            throw Failure.notSetUp
        } catch ShortcutEntryError.noAmount {
            throw Failure.noAmount
        }
        let kind = draft.type == .income ? String(localized: "income") : String(localized: "expense")
        let day = draft.occurredAt.formatted(date: .abbreviated, time: .omitted)
        try await requestConfirmation(
            actionName: .log, dialog: "Record \(draft.amount.formatted()) \(kind) on \(day)?")
        // A restore may have started while the prompt was showing; nothing else writes during one.
        guard !(await AppRouter.shared.isRestoring) else { throw Failure.unavailable }
        try await services.transactions.create(draft, now: now)
        await WidgetSync.refresh(services)
        return .result(dialog: "Recorded \(draft.amount.formatted()) \(kind).")
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
