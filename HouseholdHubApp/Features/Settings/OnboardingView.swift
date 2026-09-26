import HouseholdHubCore
import SwiftUI

/// First-launch setup (spec §24.2 addition): household currency and starting balance (§9.1).
struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(\.services) private var services
    @State private var currencyCode = OnboardingView.defaultCurrencyCode
    @State private var balanceText = ""
    @State private var asOf = Date.now
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Navigation-link style: full currency names get their own list instead of truncating in the
                    // row at large accessibility text sizes.
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(OnboardingView.currencyChoices, id: \.self) { code in
                            Text(OnboardingView.currencyLabel(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Amounts are stored in this currency. It can't be changed once you've recorded anything.")
                }
                Section {
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel("Starting balance")
                        .accessibilityIdentifier("onboarding.balance")
                    DatePicker("As of", selection: $asOf, in: ...Date.now, displayedComponents: .date)
                } header: {
                    Text("Starting balance")
                } footer: {
                    Text("What your household account held when this day began. Its transactions are added on top.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("onboarding.error")
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Get Started") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("onboarding.start")
                }
            }
        }
    }

    private func save() async {
        guard let services, !isSaving else { return }
        let trimmed = balanceText.trimmingCharacters(in: .whitespaces)
        let decimal = trimmed.isEmpty ? Decimal(0) : LedgerFormat.parseDecimal(trimmed)
        guard let decimal, let currency = try? Currency(code: currencyCode),
            let balance = try? Money(decimal: decimal, currency: currency)
        else {
            errorMessage = String(localized: "Enter the starting balance as a number, for example 1250.50.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        let now = Date.now
        do {
            let date = Self.baselineDate(asOf, now: now)
            try await services.transactions.completeOnboarding(
                currencyCode: currency.code, startingBalance: balance, asOf: date, now: now)
            onDone()
        } catch {
            errorMessage = String(localized: "Setup couldn't be saved. Please try again.")
        }
    }

    /// The start of the chosen day in the household calendar (CLAUDE.md §5: dates go through `HouseholdCalendar`),
    /// so a date picked without a time never keeps the time of day it was created at: the whole day's transactions
    /// count on top of the baseline, whatever time setup happened.
    static func baselineDate(_ picked: Date, now: Date) -> Date {
        min(HouseholdCalendar(timeZone: .current).startOfDay(for: picked), now)
    }

    static var defaultCurrencyCode: String {
        let local = Locale.current.currency?.identifier ?? "CAD"
        return (try? Currency(code: local).code) ?? "CAD"
    }

    static var currencyChoices: [String] {
        var codes = [defaultCurrencyCode]
        for code in ["CAD", "USD", "EUR", "GBP", "AUD", "MXN", "JPY"] where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }

    static func currencyLabel(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}

#Preview {
    OnboardingView {}
}
