import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget › Recurring (spec §24.2): series definitions with their next due date. Posting an occurrence creates
/// exactly one transaction (§9.4). A series can be edited (future occurrences only) and deleted while nothing has
/// been posted from it; after that it can be disabled.
struct RecurringListView: View {
    @Environment(\.services) private var services
    @Query(sort: \RecurringTransaction.createdAt) private var series: [RecurringTransaction]
    @State private var isCreating = false
    @State private var editing: RecurringTransaction?
    @State private var deleting: RecurringTransaction?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if series.isEmpty {
                ContentUnavailableView {
                    Label("No recurring items", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Add rent, salary, or subscriptions to see them in your projection.")
                } actions: {
                    Button("Add recurring item") { isCreating = true }
                        .accessibilityIdentifier("recurring.addEmpty")
                }
            } else {
                List {
                    ForEach(series) { item in
                        row(item)
                    }
                    if let errorMessage {
                        ErrorText(errorMessage)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add recurring item", systemImage: "plus") { isCreating = true }
                    .accessibilityIdentifier("recurring.add")
            }
        }
        .sheet(isPresented: $isCreating) { RecurringEditorView() }
        .sheet(item: $editing) { item in RecurringEditorView(series: item) }
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

    private func row(_ item: RecurringTransaction) -> some View {
        RecurringRow(item: item)
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

    static func icon(_ type: TransactionType) -> String {
        switch type {
        case .income: return "arrow.down.circle"
        case .expense: return "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: RecurringRow.icon(item.type))
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
        let rule = (try? item.rule()).map(RecurrenceFormat.describe) ?? ""
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
