import SwiftUI
import TipKit

/// Sprint 24 (item 4): contextual tips for the ten deeper features the first-run tour doesn't cover, shown with
/// Apple's TipKit (iOS 17+, on-device, free; no App Group or entitlement). `TutorialTips.configure()` loads the
/// datastore once at app start; each tip attaches at its own call site with `.popoverTip`, or as an inline `TipView`
/// where the research below rules out a popover.
///
/// Every tip carries `MaxDisplayCount(1)`: an iOS 26 popover can otherwise reappear on every tab switch (Apple
/// Developer Forums thread 805796, FB20904972) — see `docs/research/apple-api-decisions.md`.
///
/// A few tips (Bulk select, Budget history, Analytics taps) sit on controls that are visible the moment their screen
/// opens, which would collide with the first-run tour on a fresh install; those wait for the screen to have been
/// seen once or twice already, using a `Tips.Event` donated on appear. The others (Split, Undo, Refund, Import
/// presets, Recurring suggestions, Saved searches) only appear once their feature is already in reach — the control
/// itself doesn't exist, or the screen is only opened deliberately — so no extra visit gate is needed.
enum TutorialTips {
    /// Called once at app start (`HouseholdHubApp.init`). Under `-uiTesting`, tips are hidden so the 78 existing UI
    /// tests never see a popover covering a control; `-uiTestingTips` asks for the opposite, a clean datastore with
    /// every tip forced on, for the tips UI test itself. `showAllTipsForTesting`/`hideAllTipsForTesting` are iOS
    /// 17+, same as the rest of TipKit, so no extra availability check is needed here.
    static func configure() {
        let arguments = ProcessInfo.processInfo.arguments
        let forceTips = arguments.contains(LaunchArguments.uiTestingTips)
        // TipKit's own rule: resetDatastore() only takes effect for tips configured again afterward, so reset before
        // configuring, never after.
        if forceTips {
            try? Tips.resetDatastore()
        }
        try? Tips.configure([.displayFrequency(.immediate)])
        if arguments.contains(LaunchArguments.uiTesting) {
            if forceTips {
                Tips.showAllTipsForTesting()
            } else {
                Tips.hideAllTipsForTesting()
            }
        }
    }

    /// Settings "Reset tips" (Sprint 24 item 5, tips half): every tip can appear again, as if never shown.
    static func reset() {
        try? Tips.resetDatastore()
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// 1. Split…, in the transaction editor: offered on an eligible, unsplit expense or income (`TransactionEditorView`).
/// The button sits in a Form section row, not a toolbar, so the iOS 26 toolbar-popover issue doesn't apply.
struct SplitTip: Tip {
    var id: String { "tip.split" }
    var title: Text { Text("Split one payment") }
    var message: Text? {
        Text("Paid for more than one thing at once? Split… divides this into parts you can categorize separately.")
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 2. Undo, on the banner after a delete or bulk category change (`UndoBannerView`).
struct UndoTip: Tip {
    var id: String { "tip.undo" }
    var title: Text { Text("Changed your mind?") }
    var message: Text? { Text("Undo brings this back for a few seconds after a delete or a bulk change.") }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 3. Bulk select, on Budget's "Select" toolbar button. The button is visible the moment the transactions list opens,
/// so it waits for a second visit to that screen, tracked by `screenSeen`. The call site gives the button an
/// explicit `.buttonStyle` (iOS 26: a toolbar `Button` with none can fail to show its popover).
struct BulkSelectTip: Tip {
    static let screenSeen = Event(id: "tip.bulkSelect.screenSeen")

    var id: String { "tip.bulkSelect" }
    var title: Text { Text("Change several at once") }
    var message: Text? { Text("Select lets you delete or recategorize more than one transaction together.") }
    var rules: [Rule] {
        #Rule(Self.screenSeen) { $0.donations.count >= 2 }
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 4. Saved searches. Not attached to the filter `Menu` itself: iOS 26.1 reportedly doesn't show `popoverTip` on a
/// toolbar `Menu` button. Shown instead as an inline `TipView` in the More filters sheet, which is reached from the
/// same filter menu and is where a search worth saving has usually just been built.
struct SavedSearchesTip: Tip {
    var id: String { "tip.savedSearches" }
    var title: Text { Text("Save this search") }
    var message: Text? {
        Text("Once you're back in Budget, Save search… under Filter keeps this text and these filters under a name.")
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 5. Import presets, on the CSV import screen's Preset picker (`CSVImportView`); the screen is only reached by
/// deliberately importing a file, so no extra visit gate is needed. Not a toolbar control, so unaffected by the
/// toolbar-popover issues above.
struct ImportPresetsTip: Tip {
    var id: String { "tip.importPresets" }
    var title: Text { Text("Remember this bank's format") }
    var message: Text? {
        Text("Save as preset… remembers this file's columns, so the next file from the same bank maps itself.")
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 6. Recurring suggestions, on the suggestion card in Budget › Recurring (`RecurringListView`); the card itself only
/// appears once a pattern is detected, so it's already "in reach" the first time it's seen.
struct RecurringSuggestionsTip: Tip {
    var id: String { "tip.recurringSuggestions" }
    var title: Text { Text("Looks like a habit") }
    var message: Text? {
        Text("Household Hub noticed this repeats. Add it to see it in your projection, or Dismiss if it's not a bill.")
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 7. Refund…, on an expense's Refund action (`TransactionEditorView`); offered only once the expense is eligible.
struct RefundTip: Tip {
    var id: String { "tip.refund" }
    var title: Text { Text("Got some money back?") }
    var message: Text? { Text("Refund… records it against this purchase, so your spending stays accurate.") }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 8. Themes, on the theme picker wherever it lives (Settings, in this build). See the report for the one line
/// `SettingsView.swift` needs, since that file belongs to another lane.
struct ThemeTip: Tip {
    var id: String { "tip.themes" }
    var title: Text { Text("Make it yours") }
    var message: Text? { Text("Pick a style here to change the app's colors, icons and a few small animations.") }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 9. Budget history, on the month arrows in Budgets (`BudgetsListView`); visible from the first visit, so it waits
/// for a second one. The arrows are plain buttons in a list row, not a toolbar, so unaffected by the toolbar-popover
/// issues above.
struct BudgetHistoryTip: Tip {
    static let screenSeen = Event(id: "tip.budgetHistory.screenSeen")

    var id: String { "tip.budgetHistory" }
    var title: Text { Text("Look back") }
    var message: Text? { Text("These arrows step through past months, so you can see how a budget has been doing.") }
    var rules: [Rule] {
        #Rule(Self.screenSeen) { $0.donations.count >= 2 }
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// 10. Analytics taps, on the spending-by-category chart (`AnalyticsView` / `CategorySection`); visible from the
/// first visit, so it waits for a second one.
struct AnalyticsTapsTip: Tip {
    static let screenSeen = Event(id: "tip.analyticsTaps.screenSeen")

    var id: String { "tip.analyticsTaps" }
    var title: Text { Text("Tap to dig in") }
    var message: Text? { Text("Tap a slice or a bar to see exactly those transactions in Budget.") }
    var rules: [Rule] {
        #Rule(Self.screenSeen) { $0.donations.count >= 2 }
    }
    var options: [any Option] { [MaxDisplayCount(1)] }
}

/// Every Sprint 24 tip, for the "every tip has a non-empty id, title and message" unit test.
enum TutorialTipCatalog {
    static let all: [any Tip] = [
        SplitTip(), UndoTip(), BulkSelectTip(), SavedSearchesTip(), ImportPresetsTip(), RecurringSuggestionsTip(),
        RefundTip(), ThemeTip(), BudgetHistoryTip(), AnalyticsTapsTip(),
    ]
}
