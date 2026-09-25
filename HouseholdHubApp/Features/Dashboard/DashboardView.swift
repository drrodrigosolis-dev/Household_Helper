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
    @Query private var recent: [TransactionRecord]
    @Query private var recentWishes: [WishlistItem]
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
    }

    private enum Activity: Identifiable {
        case transaction(TransactionRecord)
        case wishlist(WishlistItem)

        var id: String {
            switch self {
            case .transaction(let record): return "t-\(record.id)"
            case .wishlist(let item): return "w-\(item.id)"
            }
        }

        var date: Date {
            switch self {
            case .transaction(let record): return record.occurredAt
            case .wishlist(let item): return item.updatedAt
            }
        }
    }

    /// The five latest entries across transactions and wishlist changes (spec §24.2); tasks join in Phase 5.
    private var activity: [Activity] {
        let all = recent.map(Activity.transaction) + recentWishes.map(Activity.wishlist)
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
        DashboardCard(title: "Current balance", identifier: "dashboard.current") {
            router.showBudget(.transactions, filter: posted)
        } content: {
            AmountText(summary.balance.current.formatted(), font: .largeTitle.bold())
        }
        pairLayout {
            DashboardCard(title: "Pending impact", identifier: "dashboard.pending") {
                router.showBudget(.transactions, filter: TransactionFilter(status: .pending))
            } content: {
                AmountText(summary.balance.pendingImpact.formatted(), font: .title3)
            }
            DashboardCard(title: "Spent this week", identifier: "dashboard.week") {
                router.showBudget(.transactions, filter: TransactionFilter(period: .thisWeek, status: .posted))
            } content: {
                AmountText(summary.spentThisWeek.formatted(), font: .title3)
            }
        }
        DashboardCard(title: "Projected in 30 days", identifier: "dashboard.projected") {
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
                        HStack {
                            Text(item.title ?? String(localized: "Recurring item"))
                            Spacer()
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
                    ForEach(activity) { entry in
                        switch entry {
                        case .transaction(let record):
                            TransactionRow(record: record, category: categories.first { $0.id == record.categoryID })
                        case .wishlist(let item):
                            WishlistRow(item: item)
                        }
                    }
                }
            }
        }
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
    let action: () -> Void
    let content: () -> Content

    init(
        title: LocalizedStringKey, identifier: String, action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.identifier = identifier
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
