import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Dashboard (spec §24.2): current balance, pending impact, 30-day projection, this week's spending, upcoming
/// recurring items, and recent activity. Each card deep-links into Budget's matching view.
struct DashboardView: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accountRecords: [Account]
    @Query private var recent: [TransactionRecord]
    @Query private var recentWishes: [WishlistItem]
    @Query private var recentTasks: [TaskItem]
    @State private var summary: DashboardSummary?
    @State private var loadFailed = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init() {
        var descriptor = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = 5
        _recent = Query(descriptor)
        var wishes = FetchDescriptor<WishlistItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        wishes.fetchLimit = 5
        _recentWishes = Query(wishes)
        var tasks = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        tasks.fetchLimit = 5
        _recentTasks = Query(tasks)
    }

    private enum Activity: Identifiable {
        case transaction(TransactionRecord)
        case wishlist(WishlistItem)
        case task(TaskItem)

        var id: String {
            switch self {
            case .transaction(let record): return "t-\(record.id)"
            case .wishlist(let item): return "w-\(item.id)"
            case .task(let task): return "k-\(task.id)"
            }
        }

        var date: Date {
            switch self {
            case .transaction(let record): return record.occurredAt
            case .wishlist(let item): return item.updatedAt
            case .task(let task): return task.updatedAt
            }
        }
    }

    /// The five latest entries across transactions, wishlist changes, and task changes (spec §24.2).
    private var activity: [Activity] {
        let all =
            recent.map(Activity.transaction) + recentWishes.map(Activity.wishlist) + recentTasks.map(Activity.task)
        return Array(all.sorted { $0.date > $1.date }.prefix(5))
    }

    private var includePending: Bool { settings.first?.includePendingInProjection ?? false }

    /// Any context's save, including the service actors', so balances refresh after every write.
    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let summary {
                        balanceCards(summary)
                        if summary.accounts.count > 1 {
                            accountsCard(summary.accounts)
                        }
                        upcomingCard(summary.upcoming)
                    } else if loadFailed {
                        ContentUnavailableView(
                            "Balances unavailable", systemImage: "exclamationmark.triangle",
                            description: Text("Your data is safe; the summary couldn't be calculated."))
                    } else {
                        ProgressView()
                    }
                    recentCard
                }
                .padding()
            }
            .quickAddAccess()
            .navigationTitle("Dashboard")
            .task { await refresh() }
            .onReceive(storeSaves) { _ in Task { await refresh() } }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func balanceCards(_ summary: DashboardSummary) -> some View {
        let posted = TransactionFilter(status: .posted)
        DashboardCard(
            title: "Current balance", identifier: "dashboard.current", value: summary.balance.current.formatted()
        ) {
            router.showBudget(.transactions, filter: posted)
        } content: {
            // Quick Add from the primary card as well as the floating button (spec §24.3).
            HStack(alignment: .firstTextBaseline) {
                AmountText(summary.balance.current.formatted(), font: .largeTitle.bold())
                Spacer(minLength: 8)
                Button("Add", systemImage: "plus") { router.isQuickAddPresented = true }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Quick Add")
                    .accessibilityIdentifier("dashboard.quickAdd")
            }
        }
        pairLayout {
            DashboardCard(
                title: "Pending impact", identifier: "dashboard.pending",
                value: summary.balance.pendingImpact.formatted()
            ) {
                router.showBudget(.transactions, filter: TransactionFilter(status: .pending))
            } content: {
                AmountText(summary.balance.pendingImpact.formatted(), font: .title3)
            }
            DashboardCard(
                title: "Spent this week", identifier: "dashboard.week", value: summary.spentThisWeek.formatted()
            ) {
                router.showBudget(.transactions, filter: TransactionFilter(period: .thisWeek, status: .posted))
            } content: {
                AmountText(summary.spentThisWeek.formatted(), font: .title3)
            }
        }
        DashboardCard(
            title: "Projected in 30 days", identifier: "dashboard.projected",
            value: summary.balance.projected.formatted()
        ) {
            router.showBudget(.recurring)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                AmountText(summary.balance.projected.formatted(), font: .title2)
                Toggle("Include pending", isOn: pendingBinding)
                    .font(.subheadline)
                    .accessibilityIdentifier("dashboard.includePending")
            }
        }
    }

    /// Each account's current figure (Sprint 10 decision 7); a row opens Budget filtered to that account.
    private func accountsCard(_ balances: [AccountBalance]) -> some View {
        DashboardCard(title: "Accounts", identifier: "dashboard.accounts") {
            router.showBudget(.transactions)
        } content: {
            VStack(spacing: 8) {
                ForEach(balances, id: \.accountID) { balance in
                    if let account = accountRecords.first(where: { $0.id == balance.accountID }) {
                        Button {
                            router.showBudget(.transactions, filter: TransactionFilter(accountID: account.id))
                        } label: {
                            rowLayout {
                                Label(account.name, systemImage: AccountFormat.icon(account.kind))
                                if !typeSize.isAccessibilitySize {
                                    Spacer()
                                }
                                Text(AccountFormat.balanceText(balance.snapshot.current, kind: account.kind))
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboard.account")
                    }
                }
            }
        }
    }

    private var rowLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
        }
        return AnyLayout(HStackLayout())
    }

    /// Side-by-side cards stack at accessibility text sizes so titles and amounts never break mid-word.
    private var pairLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(spacing: 16))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    private func upcomingCard(_ upcoming: [UpcomingOccurrence]) -> some View {
        DashboardCard(title: "Upcoming (7 days)", identifier: "dashboard.upcoming") {
            router.showBudget(.recurring)
        } content: {
            if upcoming.isEmpty {
                Text("Nothing due").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upcoming) { item in
                        // Stacks at accessibility sizes so title, date, and amount never squeeze each other.
                        rowLayout {
                            Text(item.title ?? String(localized: "Recurring item"))
                            if !typeSize.isAccessibilitySize {
                                Spacer()
                            }
                            Text(item.date.formatted(.dateTime.weekday(.abbreviated).day()))
                                .foregroundStyle(.secondary)
                            Text(LedgerFormat.signedAmount(item.amount, type: item.type))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var recentCard: some View {
        DashboardCard(title: "Recent activity", identifier: "dashboard.recent") {
            router.showBudget(.transactions)
        } content: {
            if activity.isEmpty {
                Text("No transactions yet. Tap + to add one.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    // Each row opens its own tab (spec §24.2 "deep-link into owning tab").
                    ForEach(activity) { entry in
                        switch entry {
                        case .transaction(let record):
                            Button {
                                router.showBudget(.transactions)
                            } label: {
                                TransactionRow(
                                    record: record, category: category(of: record), accounts: accountRecords)
                            }
                            .buttonStyle(.plain)
                        case .wishlist(let item):
                            Button {
                                router.show(.wishlist)
                            } label: {
                                WishlistRow(item: item)
                            }
                            .buttonStyle(.plain)
                        case .task(let task):
                            Button {
                                router.show(.tasks)
                            } label: {
                                TaskActivityRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func category(of record: TransactionRecord) -> CategoryRecord? {
        categories.first { $0.id == record.categoryID }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { includePending },
            set: { value in
                Task {
                    try? await services?.transactions.setIncludePendingInProjection(value, now: .now)
                    await refresh()
                }
            })
    }

    private func refresh() async {
        guard let services else { return }
        do {
            summary = try await services.transactions.dashboardSummary(
                now: .now, calendar: HouseholdCalendar(timeZone: .current))
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

/// A tappable summary card; the whole card is one accessible button that opens the related Budget view.
private struct DashboardCard<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    /// The card's figure, read with its title on the button so VoiceOver hears "Current balance, $1,234".
    let value: String?
    let action: () -> Void
    let content: () -> Content

    init(
        title: LocalizedStringKey, identifier: String, value: String? = nil, action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.identifier = identifier
        self.value = value
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(value.map { Text($0) } ?? Text(""))
            .accessibilityHint("Opens the matching Budget view")
            .accessibilityIdentifier(identifier)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    DashboardView()
        .environment(AppRouter())
}

/// A task in recent activity: its title and whether it is done, read as one element.
struct TaskActivityRow: View {
    let task: TaskItem

    private var kind: LocalizedStringKey { task.completedAt == nil ? "Task" : "Task · Completed" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .foregroundStyle(task.completedAt == nil ? Color.secondary : Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                Text(kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.activity")
    }
}
