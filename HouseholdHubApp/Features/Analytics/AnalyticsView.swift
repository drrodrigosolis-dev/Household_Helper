import Charts
import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Analytics (spec §24.2): period selector, spending by category, income vs expense trend, top merchants. Every
/// chart has the same numbers in a table and an audio-graph descriptor (§24.5). Posted transactions, plus pending
/// ones when Include pending is on (owner decision 2026-09-26). Sprint 23: categories and bars open their
/// transactions, each category shows its change vs the month before (A-018), and "Last month" sums up the previous
/// calendar month (F5).
struct AnalyticsView: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query private var budgets: [CategoryBudget]

    @State private var period: AnalyticsPeriod?
    /// The report with the period and pending choice it was computed for, so a late or stale result is never shown.
    @State private var loaded: (key: ReportKey, report: AnalyticsReport, changes: [CategoryChange])?
    /// Last month's summary (F5), with the pending choice it was computed for.
    @State private var summary: (includesPending: Bool, value: MonthSummary)?
    @State private var summaryFailed = false

    struct ReportKey: Hashable {
        let period: AnalyticsPeriod
        let includesPending: Bool
    }

    private var reportKey: ReportKey { ReportKey(period: selectedPeriod, includesPending: includesPending) }
    @State private var loadFailed = false
    private let calendar = HouseholdCalendar(timeZone: .current)

    private var selectedPeriod: AnalyticsPeriod { period ?? settings.first?.defaultAnalyticsPeriod ?? .thisMonth }

    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: periodBinding) {
                    ForEach(AnalyticsPeriod.allCases, id: \.self) { value in
                        Text(AnalyticsFormat.periodTitle(value)).tag(value)
                    }
                }
                .accessibilityIdentifier("analytics.period")
                Toggle("Include pending", isOn: includePendingBinding)
                    .accessibilityIdentifier("analytics.includePending")
            }
            if let loaded, loaded.key == reportKey {
                content(loaded.report, changes: loaded.changes)
            } else if loadFailed {
                ContentUnavailableView(
                    "Analytics unavailable", systemImage: "exclamationmark.triangle",
                    description: Text("Your data is safe; the figures couldn't be calculated."))
            } else {
                ProgressView()
            }
            if let summary, summary.includesPending == includesPending {
                MonthSummarySection(summary: summary.value, categories: categories)
            } else if summaryFailed {
                Section("Last month") {
                    ErrorText(String(localized: "Last month's summary couldn't be calculated. Your data is safe."))
                }
            }
        }
        .navigationTitle("Analytics")
        .themedScreen()
        .task(id: reportKey) { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    @ViewBuilder
    private func content(_ report: AnalyticsReport, changes: [CategoryChange]) -> some View {
        Section {
            LabeledContent("Income") { AmountText(report.income.formatted()) }
            LabeledContent("Expenses") { AmountText(report.expense.formatted()) }
            // Sprint 20: money given back lowers spending; shown so the Expenses figure adds up.
            if report.refunds.minorUnits > 0 {
                LabeledContent("Refunds") { AmountText(report.refunds.formatted()) }
                    .accessibilityIdentifier("analytics.refunds")
            }
            LabeledContent("Net") { AmountText(report.net.formatted()) }
                .accessibilityIdentifier("analytics.net")
        } header: {
            Text("Summary")
        } footer: {
            // Every figure on this screen follows the switch, so say which transactions it covers.
            if includesPending {
                Text("Includes pending transactions. Spent this week on the Dashboard counts posted ones only.")
            } else {
                Text("Posted transactions only.")
            }
        }
        if report.income.minorUnits == 0 && report.expense.minorUnits == 0 && report.refunds.minorUnits == 0 {
            Section {
                ContentUnavailableView(
                    "Nothing recorded in this period", systemImage: "chart.pie",
                    description: includesPending
                        ? Text("Posted and pending income and expenses appear here.")
                        : Text("Posted income and expenses appear here. Turn on Include pending to count those too."))
            }
        } else {
            if settings.first?.aiInsightsEnabled == true, AppInfo.onDeviceModelAvailable {
                NarrativeSection(facts: facts(report))
            }
            CategorySection(
                report: report, categories: categories, currencyCode: report.income.currencyCode, budgets: budgets,
                changes: changes, comparison: comparison, onSelect: showBudget)
            TrendSection(
                report: report, bucket: selectedPeriod.bucket, currencyCode: report.income.currencyCode,
                onSelect: showBucket(startingAt:))
            if !report.topMerchants.isEmpty {
                Section("Top merchants") {
                    ForEach(report.topMerchants) { merchant in
                        LabeledContent {
                            AmountText(merchant.total.formatted())
                        } label: {
                            Text(merchant.name)
                            Text("^[\(merchant.count) purchase](inflect: true)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func facts(_ report: AnalyticsReport) -> AnalyticsFacts {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let top = report.byCategory.prefix(3).map { slice in
            let name = slice.categoryID.flatMap { names[$0] } ?? String(localized: "Uncategorized")
            return NamedFigure(name: name, amount: slice.total.formatted())
        }
        let merchants = report.topMerchants.prefix(3).map { NamedFigure(name: $0.name, amount: $0.total.formatted()) }
        let balance: AnalyticsFacts.Balance =
            report.net.isZero ? .even : report.net.isNegative ? .deficit : .surplus
        return AnalyticsFacts(
            periodTitle: AnalyticsFormat.periodTitle(selectedPeriod), income: report.income.formatted(),
            expense: report.expense.formatted(), net: report.net.formatted(), balance: balance,
            topCategories: Array(top), topMerchants: merchants, includesPending: includesPending)
    }

    private var includesPending: Bool { settings.first?.analyticsIncludesPending ?? false }

    private var includePendingBinding: Binding<Bool> {
        Binding(
            get: { includesPending },
            set: { value in Task { try? await services?.transactions.setAnalyticsIncludesPending(value, now: .now) } })
    }

    private var periodBinding: Binding<AnalyticsPeriod> {
        Binding(
            get: { selectedPeriod },
            set: { value in
                period = value
                Task { try? await services?.transactions.setDefaultAnalyticsPeriod(value, now: .now) }
            })
    }

    private func refresh() async {
        guard let services else { return }
        let requested = reportKey
        let now = Date.now
        do {
            let result = try await services.analytics.report(period: requested.period, now: now, calendar: calendar)
            let changes = try await services.analytics.categoryChanges(
                period: requested.period, now: now, calendar: calendar)
            guard requested == reportKey else { return }
            loaded = (requested, result, changes)
            loadFailed = false
        } catch {
            guard requested == reportKey else { return }
            // Never leave earlier figures on screen under a failure.
            loaded = nil
            loadFailed = true
        }
        await refreshSummary(services, includesPending: requested.includesPending, now: now)
    }

    /// F5: last month's report, its budgets and today's goals, combined by `MonthSummary`.
    private func refreshSummary(_ services: AppServices, includesPending: Bool, now: Date) async {
        let lastMonth = AnalyticsPeriod.lastMonth.interval(now: now, calendar: calendar)
        do {
            let report = try await services.analytics.report(period: .lastMonth, now: now, calendar: calendar)
            let budgets = try await services.transactions.budgetReport(month: lastMonth.start, calendar: calendar)
            let goals = try await services.transactions.goalReport(now: now, calendar: calendar)
            let value = try MonthSummary(report: report, budgets: budgets, goals: goals)
            guard includesPending == self.includesPending else { return }
            summary = (includesPending, value)
            summaryFailed = false
        } catch {
            guard includesPending == self.includesPending else { return }
            summary = nil
            summaryFailed = true
        }
    }

    /// What the category changes compare against, for their wording.
    private var comparison: CategorySection.Comparison? {
        switch selectedPeriod {
        case .thisMonth: return .lastMonth
        case .lastMonth: return .monthBefore
        case .last3Months, .thisYear, .last12Months: return nil
        }
    }

    /// The transaction filter's closest period to the one on screen: it has no date range of its own, so a period
    /// other than this month opens every date (Sprint 5 default 5).
    private var filterPeriod: TransactionFilter.Period { selectedPeriod == .thisMonth ? .thisMonth : .all }

    /// Spec §24.2: a category opens Budget filtered to it (Sprint 5 default 5 for the period); Uncategorized opens the
    /// transactions without a category (Sprint 23).
    private func showBudget(_ categoryID: UUID?) {
        // The same statuses as the figure that was tapped: posted only, or posted and pending.
        var filter = TransactionFilter(period: filterPeriod, status: includesPending ? nil : .posted)
        // Exactly the tapped figure's dates (Sprint 23: the filter's date range, from F6).
        filter.dateRange = selectedPeriod.interval(now: .now, calendar: calendar)
        if let categoryID {
            filter.categoryID = categoryID
        } else {
            filter.uncategorizedOnly = true
        }
        router.showBudget(.transactions, filter: filter)
    }

    /// Sprint 23 (A-018): a week or month bar opens Budget › Transactions for exactly that week or month.
    private func showBucket(startingAt start: Date) {
        let component: Calendar.Component = selectedPeriod.bucket == .week ? .weekOfYear : .month
        var filter = TransactionFilter(period: .all, status: includesPending ? nil : .posted)
        if let end = calendar.calendar.date(byAdding: component, value: 1, to: start) {
            filter.dateRange = DateInterval(start: start, end: end)
        }
        router.showBudget(.transactions, filter: filter)
    }
}

enum AnalyticsFormat {
    static func periodTitle(_ period: AnalyticsPeriod) -> String {
        switch period {
        case .thisMonth: return String(localized: "This month")
        case .lastMonth: return String(localized: "Last month")
        case .last3Months: return String(localized: "Last 3 months")
        case .thisYear: return String(localized: "This year")
        case .last12Months: return String(localized: "Last 12 months")
        }
    }

    /// Chart positions only; every figure shown as text comes from the exact `Money`.
    static func plotValue(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }

    static func share(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

#Preview {
    NavigationStack {
        AnalyticsView()
    }
    .environment(AppRouter())
}
