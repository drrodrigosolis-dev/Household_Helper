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
    @State private var summary: DashboardSummary?
    @State private var loadFailed = false

    init() {
        var descriptor = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = 5
        _recent = Query(descriptor)
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
            Text(summary.balance.current.formatted())
                .font(.largeTitle.bold().monospacedDigit())
        }
        HStack(alignment: .top, spacing: 16) {
            DashboardCard(title: "Pending impact", identifier: "dashboard.pending") {
                router.showBudget(.transactions, filter: TransactionFilter(status: .pending))
            } content: {
                Text(summary.balance.pendingImpact.formatted())
                    .font(.title3.monospacedDigit())
            }
            DashboardCard(title: "Spent this week", identifier: "dashboard.week") {
                router.showBudget(.transactions, filter: TransactionFilter(period: .thisWeek, status: .posted))
            } content: {
                Text(summary.spentThisWeek.formatted())
                    .font(.title3.monospacedDigit())
            }
        }
        DashboardCard(title: "Projected in 30 days", identifier: "dashboard.projected") {
            router.showBudget(.recurring)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.balance.projected.formatted())
                    .font(.title2.monospacedDigit())
                Toggle("Include pending", isOn: pendingBinding)
                    .font(.subheadline)
                    .accessibilityIdentifier("dashboard.includePending")
            }
        }
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
            if recent.isEmpty {
                Text("No transactions yet. Tap + to add one.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { record in
                        TransactionRow(record: record, category: categories.first { $0.id == record.categoryID })
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
