import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget › Budgets (Sprint 11): each budgeted category's month — spent, what is available (the limit plus what
/// rolled over), and what is left or over. Tapping a row edits it; + adds one.
struct BudgetsListView: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query private var budgets: [CategoryBudget]
    @State private var statuses: [BudgetStatus] = []
    @State private var editing: BudgetEditorView.Mode?
    @State private var loadFailed = false

    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    var body: some View {
        Group {
            if budgets.isEmpty {
                ContentUnavailableView {
                    Label("No budgets", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Set a monthly limit on a spending category to see how much is left.")
                } actions: {
                    Button("Add budget") { editing = .create }
                        .accessibilityIdentifier("budgets.addEmpty")
                }
            } else {
                List {
                    Section {
                        ForEach(statuses, id: \.categoryID) { status in
                            if let category = categories.first(where: { $0.id == status.categoryID }) {
                                BudgetRow(status: status, category: category)
                                    .contentShape(Rectangle())
                                    .onTapGesture { edit(category) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Edits this budget")
                                    .accessibilityAction(named: "Show transactions") { showTransactions(category) }
                                    .contextMenu {
                                        Button("Edit", systemImage: "pencil") { edit(category) }
                                        Button("Show transactions", systemImage: "list.bullet") {
                                            showTransactions(category)
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text(Date.now.formatted(.dateTime.month(.wide).year()))
                    } footer: {
                        Text("Rolled-over budgets carry what was left, or overspent, into the next month.")
                    }
                    if loadFailed {
                        ErrorText(String(localized: "Budgets couldn't be calculated. Your data is safe."))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add budget", systemImage: "plus") { editing = .create }
                    .accessibilityIdentifier("budgets.add")
            }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { BudgetEditorView(mode: mode) }
        }
        .task { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    private func edit(_ category: CategoryRecord) {
        guard let budget = budgets.first(where: { $0.categoryID == category.id }) else { return }
        editing = .edit(budget)
    }

    private func showTransactions(_ category: CategoryRecord) {
        router.showBudget(.transactions, filter: TransactionFilter(period: .thisMonth, categoryID: category.id))
    }

    private func refresh() async {
        guard let services else { return }
        do {
            statuses = try await services.transactions.budgetReport(
                month: .now, calendar: HouseholdCalendar(timeZone: .current))
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

/// One budget: category, spent of available, a progress bar, and what is left or over (VoiceOver reads it as one).
struct BudgetRow: View {
    let status: BudgetStatus
    let category: CategoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                CategoryBadge(icon: category.icon, color: category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                    Text(BudgetFormat.spentLine(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(BudgetFormat.leftText(status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.isOver ? Color.red : Color.primary)
                    .multilineTextAlignment(.trailing)
            }
            ProgressView(value: min(max(status.usedFraction, 0), 1))
                .tint(BudgetFormat.tint(status))
                .accessibilityHidden(true)
            if !status.carriedIn.isZero {
                Text(BudgetFormat.carriedText(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.row")
    }
}

/// Budget wording (Sprint 11 decision 7): colour and words only.
enum BudgetFormat {
    static func spentLine(_ status: BudgetStatus) -> String {
        String(localized: "\(status.spent.formatted()) of \(status.available.formatted())")
    }

    static func leftText(_ status: BudgetStatus) -> String {
        guard status.isOver, let over = try? status.remaining.negated() else {
            return String(localized: "\(status.remaining.formatted()) left")
        }
        return String(localized: "\(over.formatted()) over")
    }

    static func carriedText(_ status: BudgetStatus) -> String {
        if status.carriedIn.minorUnits > 0 {
            return String(localized: "Includes \(status.carriedIn.formatted()) rolled over")
        }
        let taken = (try? status.carriedIn.negated()) ?? status.carriedIn
        return String(localized: "Reduced by \(taken.formatted()) overspent earlier")
    }

    static func tint(_ status: BudgetStatus) -> Color {
        if status.isOver { return .red }
        return status.usedFraction >= 0.8 ? .orange : .accentColor
    }
}
