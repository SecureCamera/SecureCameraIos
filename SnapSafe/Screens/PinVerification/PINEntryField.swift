//
//  PINEntryField.swift
//  SnapSafe
//

import SwiftUI
import UIKit

@MainActor
struct PINEntryField: UIViewRepresentable {
    @Binding var text: String
    let maxLength: Int
    let isEnabled: Bool
    let shouldFocus: Bool
    let pinType: PINType

    func makeUIView(context: Context) -> PaddedSecureTextField {
        let field = PaddedSecureTextField()
        field.isSecureTextEntry = true
        field.keyboardType = pinType == .alphanumeric ? .default : .numberPad
        field.textContentType = .oneTimeCode
        field.textAlignment = .center
        field.borderStyle = .none
        field.attributedPlaceholder = NSAttributedString(
            string: "PIN",
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        field.layer.cornerRadius = 8
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.systemGray3.cgColor
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: PaddedSecureTextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.isEnabled = isEnabled
        uiView.keyboardType = pinType == .alphanumeric ? .default : .numberPad
        context.coordinator.maxLength = maxLength
        context.coordinator.pinType = pinType

        // Hand the desired focus state to the field. The field itself owns the
        // *when* — it (re)attempts first responder on window attachment and
        // retries until it succeeds — so we no longer race the overlay/scene
        // transition from here. See `PaddedSecureTextField.wantsFocus`.
        uiView.wantsFocus = shouldFocus && isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maxLength: maxLength, pinType: pinType)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var maxLength: Int
        var pinType: PINType

        init(text: Binding<String>, maxLength: Int, pinType: PINType) {
            self._text = text
            self.maxLength = maxLength
            self.pinType = pinType
        }

        @objc func editingChanged(_ sender: UITextField) {
            let raw = sender.text ?? ""
            let filtered: String
            switch pinType {
            case .numeric:
                filtered = String(raw.filter(\.isNumber).prefix(maxLength))
            case .alphanumeric:
                filtered = String(raw.filter { $0.isLetter || $0.isNumber }.prefix(maxLength))
            }
            if filtered != raw { sender.text = filtered }
            if text != filtered { text = filtered }
        }
    }
}

final class PaddedSecureTextField: UITextField {
    private let inset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: inset) }

    // MARK: - Reliable auto-focus

    /// Upper bound on retry attempts so a genuinely un-focusable field (e.g.
    /// disabled, or never key) can't spin forever.
    private static let maxFocusAttempts = 20
    /// Spacing between retries. 20 × 0.05s = 1s ceiling, which comfortably spans
    /// the 0.15s overlay transition and any foreground settling.
    private static let focusRetryInterval: TimeInterval = 0.05

    private var focusAttemptsRemaining = 0

    /// Desired focus state, set by `PINEntryField.updateUIView`. Setting `true`
    /// makes the field keep attempting to become first responder (across runloop
    /// turns) until it succeeds or focus is no longer wanted. Setting `false`
    /// resigns. Idempotent — assigning the same value is a no-op.
    var wantsFocus = false {
        didSet {
            guard wantsFocus != oldValue else { return }
            if wantsFocus {
                armFocus()
            } else if isFirstResponder {
                resignFirstResponder()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Entering the window is the exact moment first-responder eligibility
        // changes — the precise point the old single-shot attempt used to miss.
        // Re-arm from a clean budget now that a window is available.
        if wantsFocus, window != nil {
            armFocus()
        }
    }

    private func armFocus() {
        focusAttemptsRemaining = Self.maxFocusAttempts
        attemptFocus()
    }

    private func attemptFocus() {
        guard wantsFocus, isEnabled, window != nil, !isFirstResponder else { return }
        if becomeFirstResponder() { return }

        // Not ready yet (window not key / responder transition in flight).
        // Retry on a later runloop turn until the budget is exhausted.
        guard focusAttemptsRemaining > 0 else { return }
        focusAttemptsRemaining -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusRetryInterval) { [weak self] in
            self?.attemptFocus()
        }
    }
}
