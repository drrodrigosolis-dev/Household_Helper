import Accessibility
import Charts
import HouseholdHubCore
import SwiftUI

/// Spending by category: a donut plus the same figures as a table. Tapping a slice or a row opens Budget filtered to
/// that category; the table is the non-gesture path and the data table required by spec §24.5.
struct CategorySection: View {
    let report: AnalyticsReport
    let categories: [CategoryRecord]
    let currencyCode: String
    let onSelect: (UUID?) -> Void

    @State private var selectedAngle: Double?

    private func category(_ id: UUID?) -> CategoryRecord? {
        categories.first { $0.id == id }
    }

    private func name(_ id: UUID?) -> String {
        category(id)?.name ?? String(localized: "Uncategorized")
    }

    private func color(_ id: UUID?) -> Color {
        category(id).map { Color($0.color) } ?? .gray
    }

    var body: some View {
        Section("Spending by category") {
            Chart(report.byCategory) { slice in
                SectorMark(
                    angle: .value("Amount", AnalyticsFormat.plotValue(slice.total)), innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(color(slice.categoryID))
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
                    HStack(spacing: 12) {
                        let record = category(slice.categoryID)
                        CategoryBadge(icon: record?.icon ?? "tray", color: record?.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(slice.categoryID))
                            Text(AnalyticsFormat.share(slice.share))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        AmountText(slice.total.formatted())
                    }
                }
                .foregroundStyle(.primary)
                .disabled(slice.categoryID == nil)
                .accessibilityElement(children: .combine)
                .accessibilityHint(hint(for: slice))
                .accessibilityIdentifier("analytics.category")
            }
        }
    }

    private func hint(for slice: CategorySpend) -> String {
        slice.categoryID == nil ? "" : String(localized: "Shows these transactions in Budget")
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

/// Income vs expense per week or month: grouped bars plus a table.
struct TrendSection: View {
    let report: AnalyticsReport
    let bucket: AnalyticsBucket
    let currencyCode: String

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

    private func bar(_ point: TrendPoint, kind: String, amount: Money) -> some ChartContent {
        BarMark(x: .value("Period", label(point.start)), y: .value("Amount", AnalyticsFormat.plotValue(amount)))
            .foregroundStyle(by: .value("Kind", kind))
            .position(by: .value("Kind", kind))
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
            .frame(height: 220)
            .accessibilityChartDescriptor(TrendChartDescriptor(points: labelledPoints, currencyCode: currencyCode))
            ForEach(report.trend) { point in
                LabeledContent(label(point.start)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        AmountText("+" + point.income.formatted(), font: .subheadline)
                        AmountText("−" + point.expense.formatted(), font: .subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
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
