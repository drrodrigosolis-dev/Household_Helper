import HouseholdHubCore
import Observation
import SwiftUI
import UIKit

/// Sprint 23 (F3): the Undo offer after a delete or a bulk category edit. It holds the Core snapshot in memory for a
/// few seconds (a device-session convenience, never persisted); a newer offer replaces an older one.
@MainActor
@Observable
final class UndoCenter {
    struct Banner: Equatable {
        let id = UUID()
        let message: String
        /// Nil for a notice, such as why an undo was refused.
        let undo: TransactionUndo?
    }

    private(set) var banner: Banner?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// About eight seconds (Sprint 23 hand check: six read as barely enough to notice and reach); longer with
    /// VoiceOver, which needs time to reach the button, and in UI tests, whose slow runners take seconds per element
    /// lookup. It also ends early on its own (`dismiss()`, called on Undo, another offer, or scrolling the list).
    private static var duration: Duration {
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting) {
            return .seconds(30)
        }
        return UIAccessibility.isVoiceOverRunning ? .seconds(15) : .seconds(8)
    }

    func offer(_ undo: TransactionUndo, message: String) {
        show(Banner(message: message, undo: undo))
    }

    func notify(_ message: String) {
        show(Banner(message: message, undo: nil))
    }

    /// The offered undo, taken once: the banner goes away.
    func take() -> TransactionUndo? {
        let undo = banner?.undo
        dismiss()
        return undo
    }

    func dismiss() {
        expiry?.cancel()
        expiry = nil
        banner = nil
    }

    private func show(_ banner: Banner) {
        expiry?.cancel()
        self.banner = banner
        AccessibilityNotification.Announcement(banner.message).post()
        let id = banner.id
        let duration = Self.duration
        expiry = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.banner?.id == id else { return }
            self.banner = nil
        }
    }
}

/// What the banner says.
enum UndoMessage {
    static func deleted(_ count: Int) -> String {
        String(localized: "Deleted \(count) transactions")
    }

    static func recategorized(_ count: Int) -> String {
        String(localized: "Changed the category of \(count) transactions")
    }

    static var refused: String {
        String(localized: "That can't be undone anymore. Nothing was changed.")
    }

    static func partlyUndone(failed: Int) -> String {
        String(localized: "\(failed) transactions couldn't be changed back.")
    }
}

/// The banner under the transaction list: the message and, while it can still be taken back, Undo.
struct UndoBannerView: View {
    let banner: UndoCenter.Banner
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(banner.message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if banner.undo != nil {
                Button("Undo", action: undo)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("undo.button")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undo.banner")
    }
}
