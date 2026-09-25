import HouseholdHubCore
import SwiftData
import SwiftUI

/// Creates a recurring series (spec §7.5–7.6). Only the v1 rule forms are offered; the service validates.
struct RecurringEditorView: View {
    enum RuleKind: String, CaseIterable, Identifiable {
        case weekly
        case monthlyOnDay
        case monthlyOnWeekday
        case yearly

        var id: String { rawValue }
    }

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var name = ""
    @State private var type = TransactionType.expense
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var ruleKind = RuleKind.monthlyOnDay
    @State private var interval = 1
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var dayOfMonth = Calendar.current.component(.day, from: .now)
    @State private var ordinal = 1
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var startDate = Date.now
    @State private var errorMessage: String?

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: currencyCode) }

    private var rule: RecurrenceRule {
        switch ruleKind {
        case .weekly: return .weekly(interval: interval, weekday: weekday)
        case .monthlyOnDay: return .monthlyOnDay(day: dayOfMonth)
        case .monthlyOnWeekday: return .monthlyOnWeekday(ordinal: ordinal, weekday: weekday)
        case .yearly: return .yearly(month: month, day: dayOfMonth)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Rent)", text: $name)
                        .accessibilityIdentifier("recurringEditor.name")
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("recurringEditor.amount")
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(categories.filter { !$0.isArchived && $0.kind.allows(type) }) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                }
                Section("Repeats") {
                    Picker("Repeats", selection: $ruleKind) {
                        Text("Weekly").tag(RuleKind.weekly)
                        Text("Monthly on a day").tag(RuleKind.monthlyOnDay)
                        Text("Monthly on a weekday").tag(RuleKind.monthlyOnWeekday)
                        Text("Yearly").tag(RuleKind.yearly)
                    }
                    ruleFields
                    DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    Text(RecurrenceFormat.describe(rule))
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Recurring Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(amount == nil)
                        .accessibilityIdentifier("recurringEditor.save")
                }
            }
        }
    }

    @ViewBuilder
    private var ruleFields: some View {
        switch ruleKind {
        case .weekly:
            Stepper("Every \(interval) week(s)", value: $interval, in: 1...52)
            weekdayPicker
        case .monthlyOnDay:
            Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        case .monthlyOnWeekday:
            Picker("Which", selection: $ordinal) {
                ForEach([1, 2, 3, 4], id: \.self) { value in
                    Text(RecurrenceFormat.ordinalText(value)).tag(value)
                }
                Text("Last").tag(-1)
            }
            weekdayPicker
        case .yearly:
            Picker("Month", selection: $month) {
                ForEach(1...12, id: \.self) { value in
                    Text(Calendar.current.monthSymbols[value - 1]).tag(value)
                }
            }
            Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        }
    }

    private var weekdayPicker: some View {
        Picker("Weekday", selection: $weekday) {
            ForEach(1...7, id: \.self) { value in
                Text(Calendar.current.weekdaySymbols[value - 1]).tag(value)
            }
        }
    }

    private func save() async {
        guard let services, let amount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await services.transactions.createSeries(
                templateAmount: amount, type: type, rule: rule, timeZone: .current, startDate: startDate,
                categoryID: categoryID, notes: trimmed.isEmpty ? nil : trimmed, now: .now)
            dismiss()
        } catch RecurrenceRuleError.invalid {
            errorMessage = String(localized: "That date doesn't exist in the chosen month.")
        } catch {
            errorMessage = String(localized: "This recurring item couldn't be saved.")
        }
    }
}
