import SwiftUI

/// A labelled text-field row whose whole area focuses the field. At accessibility text sizes `LabeledContent` stacks
/// the label above the field, and a tap on the label otherwise does nothing (local walks L-004 and L-005; CI run
/// 36255971156). Its field gets a Done button above the keyboard while focused.
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
            field.focused($isFocused)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        // A number pad has no Return key: Done above the keyboard puts it away (audit A-004). Only the focused row
        // adds it, so there is one Done however many rows a form has.
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
        }
    }
}
