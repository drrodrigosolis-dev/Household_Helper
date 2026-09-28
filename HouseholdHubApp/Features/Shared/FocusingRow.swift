import SwiftUI

/// A labelled text-field row whose whole area focuses the field. At accessibility text sizes `LabeledContent` stacks
/// the label above the field, and a tap on the label otherwise does nothing (local walks L-004 and L-005; CI run
/// 36255971156). While focused, its field gets a Done button in the row itself.
struct FocusingRow<Field: View>: View {
    private let label: LocalizedStringKey
    private let field: Field
    @FocusState private var isFocused: Bool

    init(_ label: LocalizedStringKey, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                field.focused($isFocused)
                // A number pad has no Return key: Done puts it away (audit A-004). It sits in the focused row rather
                // than above the keyboard, where iOS 26 floats it over the row just above and swallowed taps meant
                // for that field (Split's part 2 amount). Only the focused row shows it, so a form has one Done.
                // Its space is always kept: inserting it on focus shrank the field under the finger that had just
                // tapped its trailing edge, and the field lost focus again (CI run 36385300924).
                Button("Done", systemImage: "keyboard.chevron.compact.down") { isFocused = false }
                    .labelStyle(.iconOnly)
                    // Borderless: only the button's own area acts, so a tap elsewhere in the row still focuses.
                    .buttonStyle(.borderless)
                    .opacity(isFocused ? 1 : 0)
                    .allowsHitTesting(isFocused)
                    .accessibilityHidden(!isFocused)
                    .accessibilityHint("Hides the keyboard")
                    .accessibilityIdentifier("keyboard.done")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
