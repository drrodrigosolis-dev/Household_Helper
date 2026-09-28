import AppIntents
import HouseholdHubCore

/// Adds a wishlist item from one dictated line, "<name> for <amount>" (Sprint 25). The on-device model may shape
/// the draft where Apple Intelligence is on; the grammar decides everywhere else. Nothing is saved until the person
/// confirms what was understood, and the app lock applies as it does for Log Transaction.
struct AddToWishlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Wishlist"
    static let description: IntentDescription? = IntentDescription(
        "Adds something to your wishlist, for example “headphones for 149”.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Item", requestValueDialog: "What would you like to add? For example, headphones for 149")
    var text: String

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case unavailable
        case notSetUp
        case noName
        case invalidPrice
        case locked

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .unavailable: "Household Hub couldn't open its data."
            case .notSetUp: "Open Household Hub and finish setting it up first."
            case .noName: "There was nothing to add. Try something like “headphones for 149”."
            case .invalidPrice: "That price can't be used. Try something like “headphones for 149.99”."
            case .locked: "Household Hub is locked. Unlock it to add to your wishlist."
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let services = await SharedServices.current, !(await AppRouter.shared.isRestoring) else {
            throw Failure.unavailable
        }
        if try await services.transactions.isLockEnabled(), BiometricGate.isAvailable {
            let reason = String(localized: "Unlock Household Hub to add to your wishlist.")
            guard await BiometricGate.authenticate(reason: reason) else { throw Failure.locked }
        }
        let context = try await services.transactions.siriContext()
        let model: (any SiriDraftModel)? =
            context.understandsText && AppInfo.onDeviceModelAvailable ? OnDeviceSiriModel() : nil
        let entry: WishlistEntryDraft
        do {
            entry = try await SiriRefinement.wishlist(text: text, settings: context.settings, model: model).draft
        } catch SiriEntryError.notSetUp {
            throw Failure.notSetUp
        } catch SiriEntryError.emptyText {
            throw Failure.noName
        } catch SiriEntryError.invalidPrice {
            throw Failure.invalidPrice
        }
        guard let currencyCode = context.settings?.currencyCode else { throw Failure.notSetUp }
        if let price = entry.price {
            try await requestConfirmation(actionName: .add, dialog: "Add \(entry.name), \(price.formatted())?")
        } else {
            try await requestConfirmation(actionName: .add, dialog: "Add \(entry.name) with no price?")
        }
        // A restore may have started while the prompt was showing; nothing else writes during one.
        guard !(await AppRouter.shared.isRestoring) else { throw Failure.unavailable }
        try await services.transactions.createWishlistItem(entry.wishlistDraft(currencyCode: currencyCode), now: .now)
        return .result(dialog: "Added \(entry.name) to your wishlist.")
    }
}

/// Adds a task to the board's first column (Sprint 25, owner answer 2); the whole dictated line is its title.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description: IntentDescription? = IntentDescription(
        "Adds a task to the first column of your board, for example “call the plumber”.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Task", requestValueDialog: "What's the task? For example, call the plumber")
    var text: String

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case unavailable
        case notSetUp
        case noTitle
        case locked

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .unavailable: "Household Hub couldn't open its data."
            case .notSetUp: "Open Household Hub and finish setting it up first."
            case .noTitle: "There was no task to add. Try something like “call the plumber”."
            case .locked: "Household Hub is locked. Unlock it to add a task."
            }
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let services = await SharedServices.current, !(await AppRouter.shared.isRestoring) else {
            throw Failure.unavailable
        }
        if try await services.transactions.isLockEnabled(), BiometricGate.isAvailable {
            let reason = String(localized: "Unlock Household Hub to add a task.")
            guard await BiometricGate.authenticate(reason: reason) else { throw Failure.locked }
        }
        guard try await services.transactions.settingsSnapshot()?.onboardingCompleted == true else {
            throw Failure.notSetUp
        }
        let draft: TaskDraft
        do {
            draft = try TaskEntry.draft(text: text)
        } catch {
            throw Failure.noTitle
        }
        try await requestConfirmation(actionName: .add, dialog: "Add the task “\(draft.trimmedTitle)”?")
        guard !(await AppRouter.shared.isRestoring) else { throw Failure.unavailable }
        do {
            try await services.board.createTask(draft, now: .now)
        } catch TaskBoardError.unknownColumn {
            // No columns yet: the board is seeded when the app finishes setting up.
            throw Failure.notSetUp
        }
        return .result(dialog: "Added “\(draft.trimmedTitle)” to your board.")
    }
}
