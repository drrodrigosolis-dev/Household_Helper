import SwiftUI

/// An inline error message that VoiceOver also announces, since it appears without moving focus.
struct ErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .foregroundStyle(.red)
            .onAppear { announce(message) }
            .onChange(of: message) { _, new in announce(new) }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
