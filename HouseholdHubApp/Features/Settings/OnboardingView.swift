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
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(OnboardingView.currencyChoices, id: \.self) { code in
                            Text(OnboardingView.currencyLabel(code)).tag(code)
                        }
                    }
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
                    Text("What your household account held on this date. Transactions after it are added on top.")
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
            try await services.transactions.completeOnboarding(
                currencyCode: currency.code, startingBalance: balance, asOf: min(asOf, now), now: now)
            onDone()
        } catch {
            errorMessage = String(localized: "Setup couldn't be saved. Please try again.")
        }
    }

    private static var defaultCurrencyCode: String {
        let local = Locale.current.currency?.identifier ?? "CAD"
        return (try? Currency(code: local).code) ?? "CAD"
    }

    private static var currencyChoices: [String] {
        var codes = [defaultCurrencyCode]
        for code in ["CAD", "USD", "EUR", "GBP", "AUD", "MXN", "JPY"] where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }

    private static func currencyLabel(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}

#Preview {
    OnboardingView {}
}
