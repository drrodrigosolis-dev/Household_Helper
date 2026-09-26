import HouseholdHubCore
import SwiftData
import SwiftUI

/// Creates or edits a recurring series (spec §7.5–7.6). Only the v1 rule forms are offered; the service validates.
/// Editing changes future occurrences only (§9.4); transactions already posted from the series stay as they are.
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
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var name = ""
    /// nil = the default account; a transfer also names `toAccountID` (Sprint 10 decision 6).
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
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
    @State private var isSaving = false
    /// The series being edited; nil when creating one.
    private let seriesID: UUID?

    /// Kept as it was when editing; the editor doesn't offer an end date.
    private let endDate: Date?

    init() {
        seriesID = nil
        endDate = nil
    }

    init(series: RecurringTransaction) {
        seriesID = series.id
        _name = State(initialValue: series.notes ?? "")
        _type = State(initialValue: series.type)
        _amountText = State(initialValue: LedgerFormat.editableAmount(series.templateAmount))
        _categoryID = State(initialValue: series.categoryID)
        _startDate = State(initialValue: series.startDate)
        _accountID = State(initialValue: series.accountID)
        _toAccountID = State(initialValue: series.transferAccountID)
        switch try? series.rule() {
        case .weekly(let interval, let weekday):
            _ruleKind = State(initialValue: .weekly)
            _interval = State(initialValue: interval)
            _weekday = State(initialValue: weekday)
        case .monthlyOnDay(let day):
            _ruleKind = State(initialValue: .monthlyOnDay)
            _dayOfMonth = State(initialValue: day)
        case .monthlyOnWeekday(let ordinal, let weekday):
            _ruleKind = State(initialValue: .monthlyOnWeekday)
            _ordinal = State(initialValue: ordinal)
            _weekday = State(initialValue: weekday)
        case .yearly(let month, let day):
            _ruleKind = State(initialValue: .yearly)
            _month = State(initialValue: month)
            _dayOfMonth = State(initialValue: day)
        case nil:
            break
        }
        endDate = series.endDate
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: currencyCode) }

    /// Active accounts, plus the ones the series already uses even if archived since.
    private var pickableAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0.id == accountID || $0.id == toAccountID }
    }

    /// Active categories for the type, plus the series' own even if it was archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(type) }
    }

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
                    LabeledContent("Name") {
                        TextField("e.g. Rent", text: $name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("recurringEditor.name")
                    }
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                        if pickableAccounts.count > 1 || type == .transfer {
                            Text("Transfer").tag(TransactionType.transfer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("recurringEditor.type")
                    LabeledContent("Amount") {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("recurringEditor.amount")
                    }
                    if type != .transfer {
                        Picker("Category", selection: $categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(pickableCategories) { category in
                                Text(category.name).tag(UUID?.some(category.id))
                            }
                        }
                    }
                    if pickableAccounts.count > 1 {
                        Picker(type == .transfer ? "From" : "Account", selection: $accountID) {
                            Text("Default account").tag(UUID?.none)
                            ForEach(pickableAccounts) { account in
                                Text(account.name).tag(UUID?.some(account.id))
                            }
                        }
                        .accessibilityIdentifier("recurringEditor.account")
                    }
                    if type == .transfer {
                        Picker("To", selection: $toAccountID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(pickableAccounts) { account in
                                Text(account.name).tag(UUID?.some(account.id))
                            }
                        }
                        .accessibilityIdentifier("recurringEditor.toAccount")
                    }
                }
                Section("Repeats") {
                    Picker("Repeats", selection: $ruleKind) {
                        Text("Weekly").tag(RuleKind.weekly)
                        Text("Monthly on a day").tag(RuleKind.monthlyOnDay)
                        Text("Monthly on a weekday").tag(RuleKind.monthlyOnWeekday)
                        Text("Yearly").tag(RuleKind.yearly)
                    }
                    .pickerStyle(.navigationLink)
                    ruleFields
                    DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    Text(RecurrenceFormat.describe(rule))
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    ErrorText(errorMessage)
                }
            }
            .navigationTitle(seriesID == nil ? Text("New Recurring Item") : Text("Edit Recurring Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(amount == nil || isSaving)
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
        guard let services, let amount, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = trimmed.isEmpty ? nil : trimmed
        // A transfer has no category, and only a transfer names a destination.
        let category = type == .transfer ? nil : categoryID
        let destination = type == .transfer ? toAccountID : nil
        do {
            if let seriesID {
                try await services.transactions.updateSeries(
                    seriesID, templateAmount: amount, type: type, rule: rule, startDate: startDate, endDate: endDate,
                    categoryID: category, notes: notes, accountID: accountID, transferAccountID: destination,
                    now: .now)
            } else {
                try await services.transactions.createSeries(
                    templateAmount: amount, type: type, rule: rule, timeZone: .current, startDate: startDate,
                    categoryID: category, notes: notes, accountID: accountID, transferAccountID: destination,
                    now: .now)
            }
            dismiss()
        } catch RecurrenceRuleError.invalid {
            errorMessage = String(localized: "That date doesn't exist in the chosen month.")
        } catch LedgerError.transferNeedsTwoAccounts {
            errorMessage = String(localized: "A transfer needs two different accounts.")
        } catch {
            errorMessage = String(localized: "This recurring item couldn't be saved.")
        }
    }
}
