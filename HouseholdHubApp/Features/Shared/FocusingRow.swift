import SwiftUI

/// A labelled text-field row whose whole area focuses the field. At accessibility text sizes `LabeledContent` stacks
/// the label above the field, and a tap on the label otherwise does nothing (local walks L-004 and L-005; CI run
/// 36255971156). While focused, the row shows a Done button beside its label.
struct FocusingRow<Field: View>: View {
    private let label: LocalizedStringKey
    private let field: Field
    @FocusState private var isFocused: Bool

    init(_ label: LocalizedStringKey, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        LabeledContent {
            field.focused($isFocused)
        } label: {
            // A number pad has no Return key: Done puts it away (audit A-004). It sits beside the label of the focused
            // row: above the keyboard, iOS 26 floats it over the row just above and it swallowed taps meant for that
            // field (Split's part 2 amount); at the field's trailing edge it took the taps that place the cursor, and
            // kept hidden there it still took them (CI runs 36385300924, 36396693457). Only the focused row has it.
            HStack(spacing: 8) {
                Text(label)
                if isFocused {
                    Button("Done", systemImage: "keyboard.chevron.compact.down") { isFocused = false }
                        .labelStyle(.iconOnly)
                        // Borderless: only the button's own area acts, so a tap elsewhere in the row still focuses.
                        .buttonStyle(.borderless)
                        .accessibilityHint("Hides the keyboard")
                        .accessibilityIdentifier("keyboard.done")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
