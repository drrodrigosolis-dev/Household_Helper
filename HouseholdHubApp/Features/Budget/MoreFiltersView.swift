import HouseholdHubCore
import SwiftUI

/// Sprint 23 (F6): the filters a menu can't hold — an amount range in the household currency and custom dates.
struct MoreFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TransactionFilter
    let currencyCode: String
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var usesDates: Bool
    @State private var fromDay: Date
    @State private var toDay: Date
    private let calendar = HouseholdCalendar(timeZone: .current)

    init(filter: Binding<TransactionFilter>, currencyCode: String) {
        _filter = filter
        self.currencyCode = currencyCode
        let current = filter.wrappedValue
        let text: (Int64?) -> String = { minorUnits in
            minorUnits.map { LedgerFormat.editableAmount(Money(minorUnits: $0, currencyCode: currencyCode)) } ?? ""
        }
        _minimumText = State(initialValue: text(current.minimumAmountMinorUnits))
        _maximumText = State(initialValue: text(current.maximumAmountMinorUnits))
        _usesDates = State(initialValue: current.dateRange != nil)
        let range = current.dateRange
        _fromDay = State(initialValue: range?.start ?? .now)
        // The range ends at the start of the day after the last one shown.
        _toDay = State(initialValue: range.map { $0.end.addingTimeInterval(-1) } ?? .now)
    }

    /// An amount field's value (nil when empty) and whether its text is an amount at all.
    private func parsed(_ text: String) -> (money: Money?, isValid: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, true) }
        let money = LedgerFormat.parseAmount(trimmed, currencyCode: currencyCode)
        return (money, money != nil)
    }

    private var amountError: String? {
        let minimum = parsed(minimumText)
        let maximum = parsed(maximumText)
        guard minimum.isValid, maximum.isValid else {
            return String(localized: "Enter an amount such as 12.50, or leave it empty.")
        }
        if let low = minimum.money, let high = maximum.money, low.minorUnits > high.minorUnits {
            return String(localized: "The minimum is more than the maximum.")
        }
        return nil
    }

    private var dateError: String? {
        guard usesDates, calendar.startOfDay(for: fromDay) > calendar.startOfDay(for: toDay) else { return nil }
        return String(localized: "The first day is after the last day.")
    }

    var body: some View {
        Form {
            Section {
                FocusingRow("Minimum") {
                    TextField("Any", text: $minimumText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("filter.minimumAmount")
                }
                FocusingRow("Maximum") {
                    TextField("Any", text: $maximumText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("filter.maximumAmount")
                }
            } header: {
                Text("Amount")
            } footer: {
                if let amountError {
                    ErrorText(amountError)
                } else {
                    Text("Spending and income alike, in \(currencyCode).")
                }
            }
            Section {
                Toggle("Custom dates", isOn: $usesDates)
                    .accessibilityIdentifier("filter.customDates")
                if usesDates {
                    DatePicker("From", selection: $fromDay, displayedComponents: .date)
                        .accessibilityIdentifier("filter.fromDate")
                    DatePicker("To", selection: $toDay, displayedComponents: .date)
                        .accessibilityIdentifier("filter.toDate")
                }
            } header: {
                Text("Dates")
            } footer: {
                if let dateError {
                    ErrorText(dateError)
                } else if usesDates {
                    Text("Both days are included. Custom dates replace the period.")
                }
            }
        }
        .navigationTitle("More filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply", action: apply)
                    .disabled(amountError != nil || dateError != nil)
                    .accessibilityIdentifier("filter.apply")
            }
        }
    }

    private func apply() {
        var updated = filter
        updated.minimumAmountMinorUnits = parsed(minimumText).money?.minorUnits
        updated.maximumAmountMinorUnits = parsed(maximumText).money?.minorUnits
        if usesDates {
            let start = calendar.startOfDay(for: fromDay)
            let lastDay = calendar.startOfDay(for: toDay)
            let end = calendar.calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            // `dateError` keeps Apply off unless the first day comes first, so the interval is never negative.
            updated.dateRange = DateInterval(start: start, end: max(end, start))
            updated.period = .all
        } else {
            updated.dateRange = nil
        }
        filter = updated
        dismiss()
    }
}
