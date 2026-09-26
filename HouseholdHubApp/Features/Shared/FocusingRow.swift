import SwiftUI

/// A labelled text-field row whose whole area focuses the field. At accessibility text sizes `LabeledContent` stacks
/// the label above the field, and a tap on the label otherwise does nothing (local walks L-004 and L-005; CI run
/// 36255971156).
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
    }
}
