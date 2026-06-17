//
//  RevealableSecureField.swift
//  SnapSafe
//

import SwiftUI
import UIKit

/// A PIN entry field backed by `UITextField` so we can control behavior that
/// plain SwiftUI `SecureField` doesn't expose:
///
/// - **Single-character delete after refocus.** A secure `UITextField` purges
///   its entire contents on the first edit after it regains focus. We intercept
///   `shouldChangeCharactersIn`, apply the edit ourselves, and return `false`,
///   which bypasses that purge so backspace removes one character.
/// - **Reveal toggle.** `isSecure` flips `isSecureTextEntry` without losing the
///   typed text (UIKit otherwise drops it when secure entry changes).
/// - **Live keyboard swap.** When `isAlphanumeric` changes while the field is
///   focused, we call `reloadInputViews()` so the keyboard updates immediately.
///
/// `isAlphanumeric` is driven by the global app preference, not a per-PIN type.
@MainActor
struct RevealableSecureField: UIViewRepresentable {
    @Binding var text: String
    /// Optional outbound report of first-responder state, for callers that need
    /// to react to focus (e.g. hiding a header while editing).
    var isFocused: Binding<Bool>? = nil
    let placeholder: String
    let isAlphanumeric: Bool
    let maxLength: Int
    let isSecure: Bool
    let isEnabled: Bool

    func makeUIView(context: Context) -> PaddedPlainTextField {
        let field = PaddedPlainTextField()
        field.isSecureTextEntry = isSecure
        field.isEnabled = isEnabled
        field.keyboardType = isAlphanumeric ? .default : .numberPad
        field.textContentType = .oneTimeCode
        field.textAlignment = .center
        field.borderStyle = .none
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: PaddedPlainTextField, context: Context) {
        context.coordinator.maxLength = maxLength
        context.coordinator.isAlphanumeric = isAlphanumeric

        if uiView.text != text { uiView.text = text }
        uiView.isEnabled = isEnabled

        let desiredKeyboard: UIKeyboardType = isAlphanumeric ? .default : .numberPad
        if uiView.keyboardType != desiredKeyboard {
            uiView.keyboardType = desiredKeyboard
            if uiView.isFirstResponder { uiView.reloadInputViews() }
        }

        if uiView.isSecureTextEntry != isSecure {
            // Toggling secure entry makes UIKit drop the field's text. Re-assign
            // it so revealing/hiding preserves what the user typed.
            let saved = uiView.text
            uiView.isSecureTextEntry = isSecure
            uiView.text = nil
            uiView.text = saved
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, isAlphanumeric: isAlphanumeric, maxLength: maxLength)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let isFocused: Binding<Bool>?
        var isAlphanumeric: Bool
        var maxLength: Int

        init(text: Binding<String>, isFocused: Binding<Bool>?, isAlphanumeric: Bool, maxLength: Int) {
            self._text = text
            self.isFocused = isFocused
            self.isAlphanumeric = isAlphanumeric
            self.maxLength = maxLength
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            let updated = String(filtered(proposed).prefix(maxLength))

            // Apply the edit ourselves and return false. This bypasses the secure
            // field's "purge all text on first edit after refocus" behavior, so a
            // backspace removes a single character.
            textField.text = updated
            moveCaretToEnd(textField)
            if text != updated { text = updated }
            return false
        }

        @objc func editingChanged(_ sender: UITextField) {
            // Safety net for input paths that bypass shouldChangeCharactersIn
            // (autofill, dictation): keep the binding in sync and enforce the filter.
            let updated = String(filtered(sender.text ?? "").prefix(maxLength))
            if sender.text != updated { sender.text = updated }
            if text != updated { text = updated }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if isFocused?.wrappedValue == false { isFocused?.wrappedValue = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if isFocused?.wrappedValue == true { isFocused?.wrappedValue = false }
        }

        private func filtered(_ value: String) -> String {
            if isAlphanumeric {
                return String(value.filter { $0.isLetter || $0.isNumber })
            } else {
                return String(value.filter(\.isNumber))
            }
        }

        private func moveCaretToEnd(_ textField: UITextField) {
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
    }
}

final class PaddedPlainTextField: UITextField {
    private let inset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
}
