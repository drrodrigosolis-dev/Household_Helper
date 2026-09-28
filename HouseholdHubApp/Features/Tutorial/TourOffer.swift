import SwiftUI

/// Sprint 24: the Dashboard's one-time offer on an install set up before the tour existed. Gone for good after Start,
/// Not now, or the tour running any other way; nothing while it isn't offered.
struct TourOffer: View {
    @State private var tour = TourController.shared

    var body: some View {
        if tour.isOfferVisible {
            VStack(alignment: .leading, spacing: 10) {
                Label("New: take a quick tour", systemImage: "sparkles")
                    .themedFont(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A one-minute look at what Household Hub can do.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons }
                    VStack(alignment: .leading, spacing: 12) { buttons }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .themedSurface(cornerRadius: 16, standard: .background.secondary)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tour.offer")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Start") { tour.acceptOffer() }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tour.offer.start")
        Button("Not now") { tour.declineOffer() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tour.offer.dismiss")
    }
}
