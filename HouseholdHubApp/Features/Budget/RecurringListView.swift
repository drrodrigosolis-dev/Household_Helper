import HouseholdHubCore
import SwiftData
import SwiftUI
import TipKit

/// Budget › Recurring (spec §24.2): series definitions with their next due date. Posting an occurrence creates
/// exactly one transaction (§9.4). A series can be edited (future occurrences only) and deleted while nothing has
/// been posted from it; after that it can be disabled. Sprint 23 F2: patterns found in the history are offered above
/// the list ("Make it a bill?"); adding one opens the editor prefilled, and nothing is created until it is saved.
struct RecurringListView: View {
    @Environment(\.services) private var services
    @Query(sort: \RecurringTransaction.createdAt) private var series: [RecurringTransaction]
    @Query private var merchants: [Merchant]
    @State private var isCreating = false
    @State private var editing: RecurringTransaction?
    @State private var deleting: RecurringTransaction?
    @State private var errorMessage: String?
    @State private var suggestions = RecurringSuggestionsModel()
    @State private var suggesting: RecurringSuggestion?

    var body: some View {
        Group {
            if series.isEmpty && suggestions.visible.isEmpty {
                ContentUnavailableView {
                    EmptyStateLabel(Text("No recurring items"), systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Add rent, salary, or subscriptions to see them in your projection.")
                } actions: {
                    Button("Add recurring item") { isCreating = true }
                        .accessibilityIdentifier("recurring.addEmpty")
                }
            } else {
                List {
                    if !suggestions.visible.isEmpty {
                        Section("Suggestions") {
                            ForEach(suggestions.visible) { suggestion in
                                suggestionRow(suggestion).themedRow()
                            }
                        }
                    }
                    Section {
                        ForEach(series) { item in
                            row(item).themedRow()
                        }
                        if let errorMessage {
                            ErrorText(errorMessage)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        // Re-read on appear and whenever a series is added or removed (an added suggestion then disappears).
        .task(id: series.map(\.id)) { await suggestions.load(services) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add recurring item", systemImage: "plus") { isCreating = true }
                    .accessibilityIdentifier("recurring.add")
            }
        }
        .sheet(isPresented: $isCreating) { RecurringEditorView() }
        .sheet(item: $editing) { item in RecurringEditorView(series: item) }
        .sheet(item: $suggesting) { suggestion in RecurringEditorView(suggestion: suggestion) }
        .confirmationDialog(
            deleteTitle, isPresented: deletingBinding, titleVisibility: .visible, presenting: deleting
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Future occurrences disappear from the projection. Posted transactions are never deleted.")
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete \(deleting?.notes ?? String(localized: "Recurring item"))?")
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    /// "Streaming Co · about monthly · $17.99 — Make it a bill?" with Add and Dismiss.
    private func suggestionRow(_ suggestion: RecurringSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RecurringSuggestionsModel.text(for: suggestion))
            HStack(spacing: 12) {
                // Bordered styles, so each button takes only its own taps inside the row.
                Button("Add") { suggesting = suggestion }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("recurring.suggestion.add")
                Button("Dismiss") { suggestions.dismiss(suggestion) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("recurring.suggestion.dismiss")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recurring.suggestion")
        .popoverTip(RecurringSuggestionsTip())
    }

    private func row(_ item: RecurringTransaction) -> some View {
        RecurringRow(item: item, store: item.merchantID.flatMap { id in merchants.first { $0.id == id }?.displayName })
            .swipeActions(edge: .trailing) {
                if item.isEnabled, item.nextOccurrence != nil {
                    Button("Post") { post(item) }
                        .tint(.blue)
                }
                Button(toggleTitle(item)) { toggle(item) }
            }
            .swipeActions(edge: .leading) {
                Button("Edit") { editing = item }
                    .tint(.orange)
                // Not a destructive-role swipe: that removes the row before the dialog is answered.
                Button("Delete") { deleting = item }
                    .tint(.red)
            }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { editing = item }
                if item.isEnabled, item.nextOccurrence != nil {
                    Button("Post next occurrence", systemImage: "checkmark.circle") { post(item) }
                }
                Button(toggleTitle(item), systemImage: "pause.circle") { toggle(item) }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
            }
            // The same actions as the swipe and menu, no more: a disabled series offers no posting.
            .accessibilityActions {
                if item.isEnabled, item.nextOccurrence != nil {
                    Button("Post next occurrence") { post(item) }
                }
                Button(toggleTitle(item)) { toggle(item) }
                Button("Edit") { editing = item }
                Button("Delete") { deleting = item }
            }
    }

    private func toggleTitle(_ item: RecurringTransaction) -> LocalizedStringKey {
        item.isEnabled ? "Disable" : "Enable"
    }

    private func post(_ item: RecurringTransaction) {
        guard let services, item.isEnabled, let occurrence = item.nextOccurrence else { return }
        let id = item.id
        Task {
            do {
                try await services.transactions.materialize(seriesID: id, occurrence: occurrence, now: .now)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That occurrence couldn't be posted.")
            }
        }
    }

    private func delete(_ item: RecurringTransaction) {
        guard let services else { return }
        let id = item.id
        Task {
            do {
                try await services.transactions.deleteSeries(id)
                errorMessage = nil
            } catch LedgerError.seriesHasHistory {
                errorMessage = String(
                    localized: "Transactions were posted from this series, so it stays. Disable it to stop it instead.")
            } catch {
                errorMessage = String(localized: "That series couldn't be deleted.")
            }
        }
    }

    private func toggle(_ item: RecurringTransaction) {
        guard let services else { return }
        let id = item.id
        let enable = !item.isEnabled
        Task {
            do {
                try await services.transactions.setSeriesEnabled(enable, series: id, now: .now)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That series couldn't be changed.")
            }
        }
    }
}

private struct RecurringRow: View {
    let item: RecurringTransaction
    /// A purchase's store (Sprint 22).
    let store: String?

    static func icon(_ type: TransactionType) -> String {
        switch type {
        case .income: return "arrow.down.circle"
        case .expense: return "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        case .refund: return "arrow.uturn.backward.circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .purchase ? "cart" : RecurringRow.icon(item.type))
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.notes ?? String(localized: "Recurring item"))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(LedgerFormat.signedAmount(item.templateAmount, type: item.type))
                .monospacedDigit()
        }
        // Disabled rows say so in their detail line; secondary styling keeps text above AA contrast (half opacity
        // did not).
        .foregroundStyle(item.isEnabled ? .primary : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recurring.row")
    }

    private var detail: String {
        let described = (try? item.rule()).map(RecurrenceFormat.describe) ?? ""
        // A purchase reads "Weekly on Saturday at Costco".
        let rule: String
        if item.kind == .purchase, let store {
            rule = String(localized: "\(described) at \(store)")
        } else {
            rule = described
        }
        guard item.isEnabled else { return rule + " · " + String(localized: "Disabled") }
        guard let next = item.nextOccurrence else { return rule + " · " + String(localized: "Ended") }
        return rule + " · " + String(localized: "Next \(next.formatted(date: .abbreviated, time: .omitted))")
    }
}

/// Human-readable recurrence rules in the current locale.
enum RecurrenceFormat {
    static func describe(_ rule: RecurrenceRule) -> String {
        let calendar = Calendar.current
        switch rule {
        case .daily(let interval):
            return interval == 1 ? String(localized: "Daily") : String(localized: "Every \(interval) days")
        case .weekly(let interval, let weekday):
            let day = calendar.weekdaySymbols[weekday - 1]
            if interval == 1 {
                return String(localized: "Weekly on \(day)")
            }
            return String(localized: "Every \(interval) weeks on \(day)")
        case .monthlyOnDay(let day):
            return String(localized: "Monthly on day \(day)")
        case .monthlyOnWeekday(let ordinal, let weekday):
            let day = calendar.weekdaySymbols[weekday - 1]
            if ordinal == -1 {
                return String(localized: "Monthly on the last \(day)")
            }
            return String(localized: "Monthly on \(ordinalText(ordinal)) \(day)")
        case .yearly(let month, let day):
            let monthName = calendar.monthSymbols[month - 1]
            return String(localized: "Yearly on \(monthName) \(day)")
        }
    }

    static func ordinalText(_ ordinal: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: ordinal)) ?? String(ordinal)
    }
}

/// Recurring › Suggestions (Sprint 23 F2): what the detector found, minus what this device dismissed. Dismissals are
/// a device preference (UserDefaults, by merchant and type), never SwiftData or a backup.
@MainActor
@Observable
final class RecurringSuggestionsModel {
    static let dismissedKey = "recurring.dismissedSuggestions"

    private(set) var all: [RecurringSuggestion] = []
    private(set) var dismissals: RecurringSuggestionDismissals
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissals = RecurringSuggestionDismissals(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
    }

    var visible: [RecurringSuggestion] { dismissals.visible(all) }

    func show(_ suggestions: [RecurringSuggestion]) {
        all = suggestions
    }

    func dismiss(_ suggestion: RecurringSuggestion) {
        dismissals.dismiss(suggestion)
        defaults.set(dismissals.stored, forKey: Self.dismissedKey)
    }

    /// Reads the history; a failed read shows no suggestions rather than an error (they are only a convenience).
    func load(_ services: AppServices?) async {
        guard let services else { return }
        let calendar = HouseholdCalendar(timeZone: .current)
        let found = try? await services.transactions.recurringSuggestions(now: .now, calendar: calendar)
        show(found ?? [])
    }

    /// "Streaming Co · about monthly · $17.99 — Make it a bill?"
    static func text(for suggestion: RecurringSuggestion) -> String {
        let cadence: String
        switch suggestion.cadence {
        case .weekly: cadence = String(localized: "about weekly")
        case .biweekly: cadence = String(localized: "about every two weeks")
        case .monthly: cadence = String(localized: "about monthly")
        }
        let question: String
        if suggestion.type == .income {
            question = String(localized: "Make it recurring income?")
        } else if suggestion.kind == .purchase {
            question = String(localized: "Make it a recurring purchase?")
        } else {
            question = String(localized: "Make it a bill?")
        }
        return "\(suggestion.merchantName) · \(cadence) · \(suggestion.amount.formatted()) — \(question)"
    }
}
