import HouseholdHubCore
import SwiftUI

/// Analytics › Last month (Sprint 23, F5): the previous calendar month's income against spending, its spending
/// against its budgets, its top categories, and where each savings goal stands today. Every figure comes from
/// `MonthSummary`; this view only lays it out.
struct MonthSummarySection: View {
    let summary: MonthSummary
    let categories: [CategoryRecord]

    private var monthTitle: String {
        summary.interval.start.formatted(.dateTime.month(.wide).year())
    }

    /// The figure is after refunds; with refunds in the month the label says so, as the Summary does.
    private var expensesTitle: LocalizedStringKey {
        summary.refunds.isZero ? "Expenses" : "Expenses (net of refunds)"
    }

    private func name(_ id: UUID?) -> String {
        categories.first { $0.id == id }?.name ?? String(localized: "Uncategorized")
    }

    var body: some View {
        Section {
            LabeledContent("Month") { Text(monthTitle) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("analytics.monthSummary")
            if summary.hasActivity {
                LabeledContent("Income") { AmountText(summary.income.formatted()) }
                LabeledContent(expensesTitle) { AmountText(summary.expense.formatted()) }
                    .accessibilityIdentifier("analytics.monthSummary.expenses")
                LabeledContent("Net") { AmountText(summary.net.formatted()) }
                    .accessibilityIdentifier("analytics.monthSummary.net")
            } else {
                Text("Nothing was recorded last month.")
                    .foregroundStyle(.secondary)
            }
            if let total = summary.budgetTotal {
                budgets(total)
            }
            if !summary.topCategories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top categories")
                        .font(.subheadline.weight(.semibold))
                    ForEach(summary.topCategories) { slice in
                        LabeledContent(name(slice.categoryID)) { AmountText(slice.total.formatted()) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("analytics.monthSummary.topCategories")
            }
            if !summary.goals.isEmpty {
                goals
            }
        } header: {
            Text("Last month")
        } footer: {
            if !summary.goals.isEmpty {
                Text("Goals show where they stand today.")
            }
        }
    }

    /// Budgeted spending against what the month's budgets had available, in words as well as colour.
    private func budgets(_ total: Money) -> some View {
        LabeledContent("Budgets") {
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(localized: "\(summary.budgetSpent.formatted()) of \(total.formatted())"))
                    .foregroundStyle(summary.isOverBudgetTotal ? Color.red : Color.primary)
                if summary.overBudgetCount > 0 {
                    Text("^[\(summary.overBudgetCount) budget](inflect: true) over")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.monthSummary.budgets")
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Goals") {
                Text("\(summary.goalsReached) of \(summary.goals.count) reached")
            }
            ForEach(summary.goals) { goal in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(goal.rule.name) {
                        Text(AnalyticsFormat.share(goal.progressFraction))
                    }
                    ProgressView(value: goal.progressFraction)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.monthSummary.goals")
    }
}
