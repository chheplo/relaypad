import SwiftUI
import UIKit

struct PairingCodeField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var submit: () -> Void

    final class Field: UITextField {
        var wantsFocus = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && wantsFocus { becomeFirstResponder() }
        }
    }

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.placeholder = "XXXX-XXXX-XXXX"
        field.accessibilityLabel = "Pairing code"
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .asciiCapable
        field.returnKeyType = .go
        let base = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.owner = self
        if text != field.text { field.text = text }
        field.wantsFocus = focused
        if focused, field.window != nil, !field.isFirstResponder { field.becomeFirstResponder() }
        if !focused, field.isFirstResponder { field.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var owner: PairingCodeField
        init(owner: PairingCodeField) { self.owner = owner }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString replacement: String) -> Bool {
            let start = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) }
            guard let edit = PairingCodeEdit(display: field.text ?? "", range: range,
                                             replacement: replacement, selectionStart: start ?? range.location)
            else { return false }
            field.text = edit.text
            if let position = field.position(from: field.beginningOfDocument, offset: edit.caret) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            owner.text = edit.text
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !owner.focused { owner.focused = true }
        }
        func textFieldDidEndEditing(_ field: UITextField) {
            if owner.focused { owner.focused = false }
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            owner.submit()
            return false
        }
    }
}
