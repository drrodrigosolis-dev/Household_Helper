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
/// parser reads it; since Sprint 25 the on-device model may read a free sentence first where Apple Intelligence and
/// "Quick Add understanding" are on, and its answer is validated (`SiriRefinement`). Nothing is saved until the
/// person confirms what was understood (Sprint 8 default 6).
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
        guard let services = await SharedServices.current else { throw Failure.unavailable }
        let now = Date.now
        let calendar = HouseholdCalendar(timeZone: .current)
        // The order (restore, lock, draft, confirm, restore again, write) is `SiriIntentFlow`'s, tested in Core.
        let flow = SiriIntentFlow<(draft: TransactionDraft, categories: [QuickAddCategoryOption])>(
            isRestoring: { await AppRouter.shared.isRestoring },
            unlock: {
                // The app's own lock applies here too; otherwise the shortcut would be a way around it.
                // With no device passcode nothing can authenticate, and the app itself opens then too (AppRootView).
                guard try await services.transactions.isLockEnabled(), BiometricGate.isAvailable else { return true }
                let reason = String(localized: "Unlock Household Hub to record a transaction.")
                return await BiometricGate.authenticate(reason: reason)
            },
            draft: {
                // Sprint 25: with "Quick Add understanding" on and Apple Intelligence available, the on-device model
                // may read a free sentence ("I spent 40 on groceries at Safeway yesterday"); a category only with
                // "Category suggestions" on. Its answer is validated and the grammar's draft is used otherwise (§6).
                let context = try await services.transactions.siriContext()
                let model: (any SiriDraftModel)? =
                    context.understandsText && AppInfo.onDeviceModelAvailable ? OnDeviceSiriModel() : nil
                let categories = context.suggestsCategories ? context.categories : []
                do {
                    let refined = try await SiriRefinement.transaction(
                        text: text, settings: context.settings, categories: categories, model: model, now: now,
                        calendar: calendar)
                    return (draft: refined.draft, categories: categories)
                } catch ShortcutEntryError.notSetUp {
                    throw Failure.notSetUp
                } catch ShortcutEntryError.noAmount {
                    throw Failure.noAmount
                }
            },
            confirm: { request in
                let draft = request.draft
                let kind = Self.kind(of: draft)
                let day = draft.occurredAt.formatted(date: .abbreviated, time: .omitted)
                let amount = draft.amount.formatted()
                // Everything that will be saved is said back: the merchant and a category when the draft has them.
                let category = draft.categoryID.flatMap { id in request.categories.first { $0.id == id }?.name }
                switch (draft.merchantName, category) {
                case (let merchant?, let category?):
                    try await requestConfirmation(
                        actionName: .log, dialog: "Record \(amount) \(kind) at \(merchant) on \(day), in \(category)?")
                case (let merchant?, nil):
                    try await requestConfirmation(
                        actionName: .log, dialog: "Record \(amount) \(kind) at \(merchant) on \(day)?")
                case (nil, let category?):
                    try await requestConfirmation(
                        actionName: .log, dialog: "Record \(amount) \(kind) on \(day), in \(category)?")
                case (nil, nil):
                    try await requestConfirmation(actionName: .log, dialog: "Record \(amount) \(kind) on \(day)?")
                }
            },
            write: { request in
                _ = try await services.transactions.create(request.draft, now: now)
            }
        )
        let draft: TransactionDraft
        do {
            draft = try await flow.run().draft
        } catch SiriIntentFlowError.restoring {
            throw Failure.unavailable
        } catch SiriIntentFlowError.locked {
            throw Failure.locked
        }
        await WidgetSync.refresh(services)
        return .result(dialog: "Recorded \(draft.amount.formatted()) \(Self.kind(of: draft)).")
    }

    /// "income" or "expense", as the confirmation and the result say it.
    private static func kind(of draft: TransactionDraft) -> String {
        draft.type == .income ? String(localized: "income") : String(localized: "expense")
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
        AppShortcut(
            intent: AddToWishlistIntent(),
            phrases: [
                "Add to my wishlist in \(.applicationName)", "Add to my \(.applicationName) wishlist",
                "Add a wish in \(.applicationName)",
            ], shortTitle: "Add to Wishlist", systemImageName: "gift")
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)", "Add a \(.applicationName) task",
                "New task in \(.applicationName)",
            ], shortTitle: "Add Task", systemImageName: "checklist")
    }
}
