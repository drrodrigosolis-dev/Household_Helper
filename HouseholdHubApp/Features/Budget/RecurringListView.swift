import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget › Recurring (spec §24.2): series definitions with their next due date. Posting an occurrence creates
/// exactly one transaction (§9.4).
struct RecurringListView: View {
    @Environment(\.services) private var services
    @Query(sort: \RecurringTransaction.createdAt) private var series: [RecurringTransaction]
    @State private var isCreating = false
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
                        Text(errorMessage).foregroundStyle(.red)
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
            .contextMenu {
                if item.isEnabled, item.nextOccurrence != nil {
                    Button("Post next occurrence", systemImage: "checkmark.circle") { post(item) }
                }
                Button(toggleTitle(item), systemImage: "pause.circle") { toggle(item) }
            }
            // The same actions as the swipe and menu, no more: a disabled series offers no posting.
            .accessibilityActions {
                if item.isEnabled, item.nextOccurrence != nil {
                    Button("Post next occurrence") { post(item) }
                }
                Button(toggleTitle(item)) { toggle(item) }
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

    private func toggle(_ item: RecurringTransaction) {
        guard let services else { return }
        let id = item.id
        let enable = !item.isEnabled
        Task { try? await services.transactions.setSeriesEnabled(enable, series: id, now: .now) }
    }
}

private struct RecurringRow: View {
    let item: RecurringTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type == .income ? "arrow.down.circle" : "arrow.up.circle")
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
        .opacity(item.isEnabled ? 1 : 0.5)
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
