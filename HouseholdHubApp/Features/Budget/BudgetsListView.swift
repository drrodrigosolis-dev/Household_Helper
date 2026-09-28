import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget › Budgets (Sprint 11): each budgeted category's month — spent, what is available (the limit plus what
/// rolled over), and what is left or over. Tapping a row edits it; + adds one. Sprint 23 (A-017): previous months
/// too, a year back (or to the oldest budget's start), never past the current month.
struct BudgetsListView: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query private var budgets: [CategoryBudget]
    /// The month picked with the arrows; nil is the current month, so the screen follows the calendar.
    @State private var pickedMonth: BudgetMonth?
    /// The report with the month it was computed for, so a late result for another month is never shown.
    @State private var loaded: (month: BudgetMonth, statuses: [BudgetStatus])?
    @State private var editing: BudgetEditorView.Mode?
    @State private var loadFailed = false
    private let calendar = HouseholdCalendar(timeZone: .current)

    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    private var navigator: BudgetMonthNavigator {
        BudgetMonthNavigator(now: .now, calendar: calendar, starts: budgets.map(\.start))
    }

    private var month: BudgetMonth { navigator.clamped(pickedMonth ?? navigator.current) }

    private var isCurrentMonth: Bool { month == navigator.current }

    /// The shown month's figures, or nil while they load.
    private var statuses: [BudgetStatus]? {
        guard let loaded, loaded.month == month else { return nil }
        return loaded.statuses
    }

    var body: some View {
        Group {
            // Budgets of archived categories are hidden, so an empty report is an empty screen.
            if isCurrentMonth, statuses?.isEmpty == true, !loadFailed {
                ContentUnavailableView {
                    EmptyStateLabel(Text("No budgets"), systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Set a monthly limit on a spending category to see how much is left.")
                } actions: {
                    Button("Add budget") { editing = .create }
                        .accessibilityIdentifier("budgets.addEmpty")
                }
            } else {
                List {
                    Section {
                        monthStepper
                            .themedRow()
                    }
                    Section {
                        if let statuses {
                            if statuses.isEmpty, !loadFailed {
                                Text("No budgets this month.")
                                    .foregroundStyle(.secondary)
                                    .themedRow()
                            }
                            ForEach(statuses, id: \.categoryID) { status in
                                if let category = categories.first(where: { $0.id == status.categoryID }) {
                                    row(status, category)
                                }
                            }
                        } else if !loadFailed {
                            ProgressView()
                        }
                    } footer: {
                        if isCurrentMonth {
                            Text("Rolled-over budgets carry what was left, or overspent, into the next month.")
                        } else {
                            Text("Past months use each budget's current limit. Rollover counts from its start month.")
                        }
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
        .task(id: month) { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    private func row(_ status: BudgetStatus, _ category: CategoryRecord) -> some View {
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
            .themedRow()
    }

    /// Previous and next month around the month's name; each arrow is its own button (VoiceOver and Switch Control
    /// reach them directly), and a disabled one says why by being dimmed and announced as dimmed.
    private var monthStepper: some View {
        HStack {
            Button {
                pickedMonth = navigator.previous(of: month)
            } label: {
                Label("Previous month", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!navigator.canGoBack(from: month))
            .accessibilityIdentifier("budgets.previousMonth")
            Spacer(minLength: 8)
            Text(title(month))
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("budgets.month")
            Spacer(minLength: 8)
            Button {
                let next = navigator.next(of: month)
                pickedMonth = next == navigator.current ? nil : next
            } label: {
                Label("Next month", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!navigator.canGoForward(from: month))
            .accessibilityIdentifier("budgets.nextMonth")
        }
        // Two buttons in one row: without this, a tap anywhere in the row would trigger both.
        .buttonStyle(.borderless)
    }

    private func title(_ month: BudgetMonth) -> String {
        month.start(in: calendar).formatted(.dateTime.month(.wide).year())
    }

    private func edit(_ category: CategoryRecord) {
        guard let budget = budgets.first(where: { $0.categoryID == category.id }) else { return }
        editing = .edit(budget)
    }

    /// The current month opens this month's transactions; a past month opens the category's whole history, since
    /// the transaction filter has no month of its own.
    /// The category's transactions in the month shown (Sprint 23: a past month opens that month only).
    private func showTransactions(_ category: CategoryRecord) {
        var filter = TransactionFilter(period: isCurrentMonth ? .thisMonth : .all, categoryID: category.id)
        filter.dateRange = DateInterval(
            start: month.start(in: calendar), end: month.adding(months: 1).start(in: calendar))
        router.showBudget(.transactions, filter: filter)
    }

    private func refresh() async {
        guard let services else { return }
        let requested = month
        do {
            let result = try await services.transactions.budgetReport(
                month: requested.start(in: calendar), calendar: calendar)
            guard requested == month else { return }
            loaded = (requested, result)
            loadFailed = false
        } catch {
            guard requested == month else { return }
            loaded = nil
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
                // Sprint 23 (A-017): with rollover, "of" is the limit plus the carry, so name the limit too.
                Text(BudgetFormat.limitText(status) + " · " + BudgetFormat.carriedText(status))
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

    static func limitText(_ status: BudgetStatus) -> String {
        String(localized: "Limit \(status.limit.formatted())")
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
