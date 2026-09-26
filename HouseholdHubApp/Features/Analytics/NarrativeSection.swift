import HouseholdHubCore
import SwiftUI

/// Optional on-device summary (spec §24.2): collapsed, generated only when asked, written only from the report's
/// computed figures. The model writes placeholders and the app fills in the figures; text that writes a number of its
/// own is rejected (Sprint 7 default 4).
struct NarrativeSection: View {
    let facts: AnalyticsFacts

    @State private var isExpanded = false
    @State private var text: String?
    @State private var failed = false
    @State private var isWorking = false

    var body: some View {
        Section {
            DisclosureGroup("Summary", isExpanded: $isExpanded) {
                if let text {
                    Text(text)
                    Label("Written on this device; figures come from the report above.", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if failed {
                    Text("A summary couldn't be written this time.").foregroundStyle(.secondary)
                }
                Button(buttonTitle) { Task { await generate() } }
                    .disabled(isWorking)
                    .accessibilityIdentifier("analytics.summary.generate")
            }
        }
        .onChange(of: facts) {
            text = nil
            failed = false
        }
    }

    private var buttonTitle: LocalizedStringKey { text == nil ? "Write summary" : "Write again" }

    private func generate() async {
        isWorking = true
        defer { isWorking = false }
        let facts = self.facts
        // In the app's own language (Sprint 16), named in English for the model's instructions.
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
        let raw = await OnDeviceModel.narrate(facts, language: language)
        // The period or figures changed while the model was writing: this text describes something no longer shown.
        guard facts == self.facts else { return }
        if let raw, let checked = NarrativeValidator.validate(raw, facts: facts) {
            text = checked
            failed = false
        } else {
            failed = true
        }
    }
}
