import HouseholdHubCore
import SwiftUI

/// Settings › Household (spec §24.2 "Currency", §6.3, §9.1): corrects the starting balance and its date, and changes
/// the currency only while nothing has been recorded. A new baseline changes the current balance, so saving asks
/// first; no transaction is touched.
struct HouseholdEditorView: View {
    let settings: AppSettings

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var currencyCode: String
    @State private var balanceText: String
    @State private var asOf: Date
    @State private var currencyLocked = true
    @State private var isConfirming = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(settings: AppSettings) {
        self.settings = settings
        let balance = Money(minorUnits: settings.startingBalanceMinorUnits, currencyCode: settings.currencyCode)
        _currencyCode = State(initialValue: settings.currencyCode)
        _balanceText = State(initialValue: LedgerFormat.editableAmount(balance))
        _asOf = State(initialValue: settings.startingBalanceDate)
    }

    private var choices: [String] {
        let codes = OnboardingView.currencyChoices
        return codes.contains(settings.currencyCode) ? codes : [settings.currencyCode] + codes
    }

    /// The typed balance in the chosen currency; nil when it isn't a valid amount for it.
    private var balance: Money? {
        let trimmed = balanceText.trimmingCharacters(in: .whitespaces)
        let decimal = trimmed.isEmpty ? Decimal(0) : LedgerFormat.parseDecimal(trimmed)
        guard let decimal, let currency = try? Currency(code: currencyCode) else { return nil }
        return try? Money(decimal: decimal, currency: currency)
    }

    private var baselineChanged: Bool {
        balance?.minorUnits != settings.startingBalanceMinorUnits || asOf != settings.startingBalanceDate
    }

    var body: some View {
        Form {
            Section {
                if currencyLocked {
                    LabeledContent("Currency", value: OnboardingView.currencyLabel(settings.currencyCode))
                } else {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(choices, id: \.self) { code in
                            Text(OnboardingView.currencyLabel(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("household.currency")
                }
            } footer: {
                if currencyLocked {
                    Text(
                        """
                        Amounts you've recorded are stored in this currency, so it can't change without \
                        reinterpreting them. To use another currency, start a new data set (back up first).
                        """
                    )
                } else {
                    Text("Nothing is recorded yet, so the currency can still change.")
                }
            }
            Section {
                TextField("0.00", text: $balanceText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel("Starting balance")
                    .accessibilityIdentifier("household.balance")
                DatePicker("As of", selection: $asOf, in: ...Date.now, displayedComponents: .date)
            } header: {
                Text("Starting balance")
            } footer: {
                Text("What the household account held on this date. Changing it changes the current balance.")
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if baselineChanged {
                        isConfirming = true
                    } else {
                        Task { await save() }
                    }
                }
                .disabled(balance == nil || isSaving)
                .accessibilityIdentifier("household.save")
            }
        }
        .confirmationDialog("Change the starting balance?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Change Starting Balance") { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current and projected balances are recalculated from the new baseline. No transaction changes.")
        }
        .task {
            currencyLocked = (try? await services?.transactions.isCurrencyLocked()) ?? true
        }
    }

    private func save() async {
        guard let services, let balance, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let now = Date.now
        do {
            try await services.transactions.updateHousehold(
                currencyCode: currencyCode, startingBalance: balance, asOf: min(asOf, now), now: now)
            await WidgetSync.refresh(services)
            dismiss()
        } catch LedgerError.currencyLockedByExistingRecords {
            currencyLocked = true
            currencyCode = settings.currencyCode
            errorMessage = String(localized: "Something was recorded meanwhile, so the currency can't change now.")
        } catch {
            errorMessage = String(localized: "The household settings couldn't be saved.")
        }
    }
}
