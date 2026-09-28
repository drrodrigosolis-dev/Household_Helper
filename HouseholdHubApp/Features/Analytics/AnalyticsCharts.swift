import Accessibility
import Charts
import HouseholdHubCore
import SwiftUI

/// Spending by category: a donut plus the same figures as a table. Tapping a slice or a row opens Budget filtered to
/// that category (Uncategorized too, Sprint 23); the table is the non-gesture path and the data table required by
/// spec §24.5. Each row shows its change vs the month before when the period is a single month (A-018).
struct CategorySection: View {
    /// The month the changes compare against, for their wording.
    enum Comparison {
        case lastMonth
        case monthBefore
    }

    let report: AnalyticsReport
    let categories: [CategoryRecord]
    let currencyCode: String
    /// Category budgets, so each budgeted category shows its monthly limit (Sprint 11).
    var budgets: [CategoryBudget] = []
    /// Each category's change vs the month before; empty when the period has no comparison.
    var changes: [CategoryChange] = []
    var comparison: Comparison?
    let onSelect: (UUID?) -> Void

    @State private var selectedAngle: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
    }
    @Environment(\.colorScheme) private var colorScheme

    private func category(_ id: UUID?) -> CategoryRecord? {
        categories.first { $0.id == id }
    }

    private func name(_ id: UUID?) -> String {
        category(id)?.name ?? String(localized: "Uncategorized")
    }

    /// In Dark Mode, category colors are lightened just enough to keep 3:1 against the chart's background.
    private func color(_ id: UUID?) -> Color {
        guard let token = category(id)?.color else { return .gray }
        return Color(colorScheme == .dark ? token.ensuringContrast(against: .darkSecondaryBackground) : token)
    }

    var body: some View {
        Section("Spending by category") {
            Chart(report.byCategory) { slice in
                SectorMark(
                    angle: .value("Amount", AnalyticsFormat.plotValue(slice.total)), innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(color(slice.categoryID))
                // Each mark is its own VoiceOver element: say which category and how much, with currency.
                .accessibilityLabel(name(slice.categoryID))
                .accessibilityValue(slice.total.formatted())
            }
            .chartAngleSelection(value: $selectedAngle)
            .frame(height: 220)
            .accessibilityChartDescriptor(CategoryChartDescriptor(rows: rows, currencyCode: currencyCode))
            .onChange(of: selectedAngle) { _, angle in
                guard let angle, let hit = slice(at: angle) else { return }
                selectedAngle = nil
                onSelect(hit.categoryID)
            }
            ForEach(report.byCategory) { slice in
                Button {
                    onSelect(slice.categoryID)
                } label: {
                    // At accessibility sizes the amount moves under the name, so names never break mid-word
                    // (walk run 36214979821 showed "Un-cate-go-rized").
                    rowLayout {
                        HStack(spacing: 12) {
                            let record = category(slice.categoryID)
                            CategoryBadge(icon: record?.icon ?? "tray", color: record?.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(slice.categoryID))
                                Text(caption(for: slice))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let comparison, let change = changes.first(where: { $0.id == slice.id }) {
                                    ChangeLine(change: change, comparison: comparison)
                                }
                            }
                            .layoutPriority(1)
                        }
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 8)
                        }
                        AmountText(slice.total.formatted())
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Shows these transactions in Budget"))
                .accessibilityIdentifier("analytics.category")
            }
        }
    }

    private func caption(for slice: CategorySpend) -> String {
        let share = AnalyticsFormat.share(slice.share)
        guard let budget = budgets.first(where: { $0.categoryID == slice.categoryID }) else { return share }
        return share + " · " + String(localized: "limit \(budget.limit.formatted()) a month")
    }

    private var rows: [(String, Double)] {
        report.byCategory.map { (name($0.categoryID), AnalyticsFormat.plotValue($0.total)) }
    }

    /// The slice whose cumulative range contains `angle` (Swift Charts reports the selection in value units).
    private func slice(at angle: Double) -> CategorySpend? {
        var running = 0.0
        for slice in report.byCategory {
            running += AnalyticsFormat.plotValue(slice.total)
            if angle <= running {
                return slice
            }
        }
        return nil
    }
}

/// Income vs expense per week or month: grouped bars plus a table. Tapping a bar or a row opens that week's or month's
/// transactions in Budget (Sprint 23, A-018); the rows are the non-gesture path.
struct TrendSection: View {
    let report: AnalyticsReport
    let bucket: AnalyticsBucket
    let currencyCode: String
    /// Called with the start of the tapped week or month.
    let onSelect: (Date) -> Void

    @State private var selectedLabel: String?

    private var labelledPoints: [(String, TrendPoint)] {
        report.trend.map { (label($0.start), $0) }
    }

    /// A week that began in the previous month is labelled by its first day inside the period.
    private func label(_ start: Date) -> String {
        let date = max(start, report.interval.start)
        switch bucket {
        case .week: return date.formatted(.dateTime.month(.abbreviated).day())
        case .month: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    private var incomeLabel: String { String(localized: "Income") }
    private var expenseLabel: String { String(localized: "Expenses") }

    /// Says which figure is which: the visible +/− column alone reads as two unlabelled amounts.
    private func rowLabel(_ point: TrendPoint) -> Text {
        let period = label(point.start)
        let income = point.income.formatted()
        let expense = point.expense.formatted()
        return Text("\(period): income \(income), expenses \(expense)")
    }

    private func bar(_ point: TrendPoint, kind: String, amount: Money) -> some ChartContent {
        BarMark(x: .value("Period", label(point.start)), y: .value("Amount", AnalyticsFormat.plotValue(amount)))
            .foregroundStyle(by: .value("Kind", kind))
            .position(by: .value("Kind", kind))
            .accessibilityLabel("\(kind), \(label(point.start))")
            .accessibilityValue(amount.formatted())
    }

    var body: some View {
        Section("Income vs expenses") {
            Chart {
                ForEach(report.trend) { point in
                    bar(point, kind: incomeLabel, amount: point.income)
                    bar(point, kind: expenseLabel, amount: point.expense)
                }
            }
            .chartForegroundStyleScale([incomeLabel: Color.green, expenseLabel: Color.red])
            .chartXSelection(value: $selectedLabel)
            .frame(height: 220)
            .accessibilityChartDescriptor(TrendChartDescriptor(points: labelledPoints, currencyCode: currencyCode))
            .onChange(of: selectedLabel) { _, selected in
                guard let selected, let hit = labelledPoints.first(where: { $0.0 == selected }) else { return }
                selectedLabel = nil
                onSelect(hit.1.start)
            }
            ForEach(report.trend) { point in
                Button {
                    onSelect(point.start)
                } label: {
                    LabeledContent(label(point.start)) {
                        VStack(alignment: .trailing, spacing: 2) {
                            AmountText("+" + point.income.formatted(), font: .subheadline)
                            AmountText("−" + point.expense.formatted(), font: .subheadline)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowLabel(point))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Shows these transactions in Budget"))
                .accessibilityIdentifier("analytics.trend")
            }
        }
    }
}

/// A category's change vs the month before: an arrow and the amount, read by VoiceOver as one sentence ("up $12.00
/// from last month"). The arrow is never the only signal: the words say which way.
struct ChangeLine: View {
    let change: CategoryChange
    let comparison: CategorySection.Comparison

    private var arrow: String {
        switch change.direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .same: return "equal"
        }
    }

    private var sentence: String {
        let amount = change.difference.formatted()
        switch (change.direction, comparison) {
        case (.up, .lastMonth): return String(localized: "up \(amount) from last month")
        case (.down, .lastMonth): return String(localized: "down \(amount) from last month")
        case (.same, .lastMonth): return String(localized: "same as last month")
        case (.up, .monthBefore): return String(localized: "up \(amount) from the month before")
        case (.down, .monthBefore): return String(localized: "down \(amount) from the month before")
        case (.same, .monthBefore): return String(localized: "same as the month before")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: arrow)
                .accessibilityHidden(true)
            Text(sentence)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
        .accessibilityIdentifier("analytics.category.change")
    }
}

// MARK: Audio graphs (spec §24.5)

struct CategoryChartDescriptor: AXChartDescriptorRepresentable {
    let rows: [(String, Double)]
    let currencyCode: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxValue = rows.map(\.1).max() ?? 0
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Category"), categoryOrder: rows.map(\.0))
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"), range: 0...max(maxValue, 1), gridlinePositions: []
        ) { [currencyCode] value in value.formatted(.currency(code: currencyCode)) }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Spending"), isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.0, y: $0.1) })
        return AXChartDescriptor(
            title: String(localized: "Spending by category"), summary: nil, xAxis: xAxis, yAxis: yAxis,
            additionalAxes: [], series: [series])
    }
}

struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let points: [(String, TrendPoint)]
    let currencyCode: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let income = points.map { ($0.0, AnalyticsFormat.plotValue($0.1.income)) }
        let expense = points.map { ($0.0, AnalyticsFormat.plotValue($0.1.expense)) }
        let maxValue = (income + expense).map(\.1).max() ?? 0
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Period"), categoryOrder: points.map(\.0))
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"), range: 0...max(maxValue, 1), gridlinePositions: []
        ) { [currencyCode] value in value.formatted(.currency(code: currencyCode)) }
        let series = [
            AXDataSeriesDescriptor(
                name: String(localized: "Income"), isContinuous: false,
                dataPoints: income.map { AXDataPoint(x: $0.0, y: $0.1) }),
            AXDataSeriesDescriptor(
                name: String(localized: "Expenses"), isContinuous: false,
                dataPoints: expense.map { AXDataPoint(x: $0.0, y: $0.1) }),
        ]
        return AXChartDescriptor(
            title: String(localized: "Income vs expenses"), summary: nil, xAxis: xAxis, yAxis: yAxis,
            additionalAxes: [], series: series)
    }
}
