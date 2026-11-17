import SwiftUI
import UIKit

struct PairingCodeField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var submit: () -> Void

    final class Field: UITextField {
        var wantsFocus = false

        override func deleteBackward() {
            guard let coordinator = delegate as? Coordinator, let selection = selectedTextRange else {
                super.deleteBackward()
                return
            }
            let start = offset(from: beginningOfDocument, to: selection.start)
            let end = offset(from: beginningOfDocument, to: selection.end)
            let first = selection.isEmpty ? max(0, start - 1) : start
            _ = coordinator.replace(in: self, range: NSRange(location: first, length: end - first), with: "")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && wantsFocus { becomeFirstResponder() }
        }
    }

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.pasteDelegate = context.coordinator
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

    final class Coordinator: NSObject, UITextFieldDelegate, UITextPasteDelegate {
        var owner: PairingCodeField
        init(owner: PairingCodeField) { self.owner = owner }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString replacement: String) -> Bool {
            _ = replace(in: field, range: range, with: replacement)
            return false
        }

        func textPasteConfigurationSupporting(_ input: UITextPasteConfigurationSupporting,
                                              performPasteOf string: NSAttributedString,
                                              to target: UITextRange) -> UITextRange {
            guard let field = input as? UITextField else { return target }
            let start = field.offset(from: field.beginningOfDocument, to: target.start)
            let end = field.offset(from: field.beginningOfDocument, to: target.end)
            // UIKit would otherwise move by the length of the pasted text, omitting inserted dashes.
            return replace(in: field, range: NSRange(location: start, length: end - start),
                           with: string.string) ?? target
        }

        func replace(in field: UITextField, range: NSRange, with replacement: String) -> UITextRange? {
            let start = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) }
            guard let edit = PairingCodeEdit(display: field.text ?? "", range: range,
                                             replacement: replacement, selectionStart: start ?? range.location)
            else { return field.selectedTextRange }
            field.text = edit.text
            owner.text = edit.text
            guard let position = field.position(from: field.beginningOfDocument, offset: edit.caret) else { return nil }
            let caret = field.textRange(from: position, to: position)
            field.selectedTextRange = caret
            return caret
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
