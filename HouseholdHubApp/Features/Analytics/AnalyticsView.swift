import Charts
import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Analytics (spec §24.2): period selector, spending by category, income vs expense trend, top merchants. Every
/// chart has the same numbers in a table and an audio-graph descriptor (§24.5). Posted transactions only (Sprint 5
/// default 2).
struct AnalyticsView: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    @State private var period: AnalyticsPeriod?
    @State private var report: AnalyticsReport?
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
            }
            if let report {
                content(report)
            } else if loadFailed {
                ContentUnavailableView(
                    "Analytics unavailable", systemImage: "exclamationmark.triangle",
                    description: Text("Your data is safe; the figures couldn't be calculated."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Analytics")
        .task(id: selectedPeriod) { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    @ViewBuilder
    private func content(_ report: AnalyticsReport) -> some View {
        Section("Summary") {
            LabeledContent("Income") { AmountText(report.income.formatted()) }
            LabeledContent("Expenses") { AmountText(report.expense.formatted()) }
            LabeledContent("Net") { AmountText(report.net.formatted()) }
                .accessibilityIdentifier("analytics.net")
        }
        if report.income.minorUnits == 0 && report.expense.minorUnits == 0 {
            Section {
                ContentUnavailableView(
                    "Nothing posted in this period", systemImage: "chart.pie",
                    description: Text("Posted income and expenses appear here. Pending items are not counted."))
            }
        } else {
            CategorySection(report: report, categories: categories, onSelect: showBudget)
            TrendSection(report: report, bucket: selectedPeriod.bucket)
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
        do {
            report = try await services.analytics.report(period: selectedPeriod, now: .now, calendar: calendar)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Spec §24.2: a category opens Budget filtered to it (Sprint 5 default 5 for the period).
    private func showBudget(_ categoryID: UUID?) {
        guard let categoryID else { return }
        let range: TransactionFilter.Period = selectedPeriod == .thisMonth ? .thisMonth : .all
        router.showBudget(.transactions, filter: TransactionFilter(period: range, categoryID: categoryID))
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
