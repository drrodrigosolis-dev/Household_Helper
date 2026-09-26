import HouseholdHubCore
import SwiftUI

/// Optional on-device summary (spec §24.2): collapsed, generated only when asked, written only from the report's
/// computed figures, and rejected if it quotes a number that is not one of them (Sprint 7 default 4).
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
                    Label("Written on this device from the figures above.", systemImage: "sparkles")
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
        if let raw = await OnDeviceModel.narrate(facts), let checked = NarrativeValidator.validate(raw, facts: facts) {
            text = checked
            failed = false
        } else {
            failed = true
        }
    }
}
