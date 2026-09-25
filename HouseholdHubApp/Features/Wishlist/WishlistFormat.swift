import HouseholdHubCore
import SwiftUI
import UIKit

enum WishlistFormat {
    static func priorityText(_ priority: Priority) -> String {
        switch priority {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        }
    }

    static func statusText(_ status: WishlistStatus) -> String {
        switch status {
        case .wanted: return String(localized: "Wanted")
        case .pending: return String(localized: "Pending")
        case .purchased: return String(localized: "Purchased")
        case .archived: return String(localized: "Archived")
        }
    }

    /// "Price unknown" for a zero estimate, never "$0.00", so a missing estimate is not mistaken for free.
    static func estimateText(_ money: Money) -> String {
        money.minorUnits == 0 ? String(localized: "Price unknown") : money.formatted()
    }

    static func priorityIcon(_ priority: Priority) -> String {
        switch priority {
        case .low: return "arrow.down"
        case .medium: return "equal"
        case .high: return "exclamationmark"
        }
    }
}

/// An item's thumbnail from the image store, or a neutral placeholder. Decorative: cards describe items in text.
struct WishlistThumbnail: View {
    let reference: String?
    var size: CGFloat? = 56

    @Environment(\.services) private var services
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "gift")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            .task(id: reference) { await load() }
    }

    private func load() async {
        guard let reference, let url = try? services?.images?.thumbnailURL(for: reference) else {
            image = nil
            return
        }
        let path = url.path(percentEncoded: false)
        image = await Task.detached { UIImage(contentsOfFile: path) }.value
    }
}
