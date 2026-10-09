# Alphanumeric PIN Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to opt into an alphanumeric PIN (letters + numbers) at setup time, storing the PIN type alongside the hash so verification shows the right keyboard.

**Architecture:** `PINType` is embedded in `HashedPin` so type and credential are always in sync. The toggle appears above the PIN fields at setup time, defaults to off (numeric), and is fixed once the PIN is set. Main PIN and Poison Pill PIN each carry their own independent type.

**Tech Stack:** Swift, SwiftUI, UIKit (`UITextField`), XCTest, Mockable (`@Mockable`, `given`/`verify`), FactoryKit (`@Injected`)

**Spec:** `docs/superpowers/specs/2026-06-15-alphanumeric-pin-design.md`

---

## File Map

**New files:**
- `SnapSafe/Data/PIN/PINType.swift`
- `SnapSafeTests/PinStrengthCheckUseCaseTests.swift`

**Modified files:**
- `SnapSafe/Data/PIN/HashedPin.swift`
- `SnapSafe/Data/PIN/PinRepository.swift`
- `SnapSafe/Data/PIN/PinRepositoryImpl.swift`
- `SnapSafe/Data/UseCases/PinStrengthCheckUseCase.swift`
- `SnapSafe/Data/UseCases/CreatePinUseCase.swift`
- `SnapSafe/Data/UseCases/CreatePoisonPillUseCase.swift`
- `SnapSafe/Screens/PinVerification/PINEntryField.swift`
- `SnapSafe/Screens/PinSetup/PINSetupViewModel.swift`
- `SnapSafe/Screens/PinSetup/PINSetupView.swift`
- `SnapSafe/Screens/PinVerification/PINVerificationViewModel.swift`
- `SnapSafe/Screens/PinVerification/PINVerificationView.swift`
- `SnapSafe/Screens/PoisonPillSetup/PoisonPillSetupWizardViewModel.swift`
- `SnapSafe/Screens/PoisonPillSetup/PoisonPillPinCreationView.swift`
- `SnapSafeTests/PinRepositoryTest.swift`

> **Note:** `SnapSafe/ViewModels/PINSetupViewModel.swift` is a legacy duplicate — do not modify it.

---

### Task 1: PINType enum

**Files:**
- Create: `SnapSafe/Data/PIN/PINType.swift`

- [ ] **Step 1: Create the file**

```swift
// SnapSafe/Data/PIN/PINType.swift

enum PINType: String, Codable, Sendable {
    case numeric
    case alphanumeric
}
```

- [ ] **Step 2: Build to confirm it compiles**

In Xcode: **Product → Build** (⌘B). Expected: success with no errors.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Data/PIN/PINType.swift
git commit -m "feat: add PINType enum for numeric/alphanumeric PIN support"
```

---

### Task 2: Add pinType to HashedPin

`HashedPin` gains a `var pinType: PINType = .numeric`. Using `var` (not `let`) so the repository can assign it after hashing. The default `.numeric` means existing stored values decode cleanly without migration — `JSONDecoder` uses the default when the key is absent.

**Files:**
- Modify: `SnapSafe/Data/PIN/HashedPin.swift`

- [ ] **Step 1: Update HashedPin**

Replace the entire file content:

```swift
// SnapSafe/Data/PIN/HashedPin.swift

struct HashedPin: Codable, Equatable, Sendable {
    let hash: String
    let salt: String
    var pinType: PINType = .numeric
}
```

- [ ] **Step 2: Build to confirm it compiles**

In Xcode: **Product → Build** (⌘B). Expected: success. Existing `HashedPin(hash:salt:)` callsites still compile because `pinType` has a default.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Data/PIN/HashedPin.swift
git commit -m "feat: embed PINType in HashedPin with backward-compatible default"
```

---

### Task 3: Update PinRepository protocol

Add `pinType` parameters to `setAppPin` and `setPoisonPillPin`. The `@Mockable` macro regenerates `MockPinRepository` automatically when you build.

**Files:**
- Modify: `SnapSafe/Data/PIN/PinRepository.swift`

- [ ] **Step 1: Update the protocol**

Replace the `setAppPin` and `setPoisonPillPin` lines:

```swift
// SnapSafe/Data/PIN/PinRepository.swift

import Mockable

@Mockable
protocol PinRepository: Sendable {
    // MARK: - Core PIN APIs

    func setAppPin(_ pin: String, pinType: PINType) async
    func getHashedPin() async -> HashedPin?

    func hashPin(_ pin: String) async throws -> HashedPin
    func verifyPin(inputPin: String, storedHash: HashedPin) async -> Bool
    func verifyPoisonPillPin(_ pin: String) async -> Bool

    func verifySecurityPin(_ pin: String) async -> Bool
    func hasPoisonPillPin() async -> Bool

    // MARK: - Poison Pill APIs

    func setPoisonPillPin(_ pin: String, pinType: PINType) async
    func getPlainPoisonPillPin() async -> String?
    func getHashedPoisonPillPin() async -> HashedPin?
    func activatePoisonPill() async
    func removePoisonPillPin() async
}

let MIN_PIN_LENGTH = 4
let MAX_PIN_LENGTH = 10
```

- [ ] **Step 2: Build — expect compiler errors at callsites**

In Xcode: **Product → Build** (⌘B). Expected: errors at every `setAppPin` and `setPoisonPillPin` callsite. These get fixed in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Data/PIN/PinRepository.swift
git commit -m "feat: add pinType parameter to PinRepository setAppPin and setPoisonPillPin"
```

---

### Task 4: Update PinRepositoryImpl + fix existing tests

`PinRepositoryImpl` sets `hashedPin.pinType = pinType` after hashing, then encodes and stores. Existing repository tests need their `setAppPin`/`setPoisonPillPin` calls updated to pass `pinType`.

**Files:**
- Modify: `SnapSafe/Data/PIN/PinRepositoryImpl.swift`
- Modify: `SnapSafeTests/PinRepositoryTest.swift`

- [ ] **Step 1: Update `setAppPin` in PinRepositoryImpl**

Replace the existing `setAppPin` method:

```swift
func setAppPin(_ pin: String, pinType: PINType) async {
    do {
        var hashedPin = try await hashPin(pin)
        hashedPin.pinType = pinType
        let hashedPinData = try jsonEncoder().encode(hashedPin)
        let cipheredHash = try await encryptionScheme.encryptWithKeyAlias(
            plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
        let cipheredHashBase64 = cipheredHash.base64EncodedString()
        await dataSource.setAppPin(cipheredPin: cipheredHashBase64)
    } catch {
        Logger.storage.error("Failed to store app pin: \(error)")
    }
}
```

- [ ] **Step 2: Update `setPoisonPillPin` in PinRepositoryImpl**

Replace the existing `setPoisonPillPin` method:

```swift
func setPoisonPillPin(_ pin: String, pinType: PINType) async {
    do {
        var hashedPin = try await hashPin(pin)
        hashedPin.pinType = pinType
        let hashedPinData = try jsonEncoder().encode(hashedPin)

        Logger.security.debug("Setting poison pill PIN", metadata: [
            "hashedPinDataSize": .stringConvertible(hashedPinData.count)
        ])

        let cipheredHashedPpp = try await encryptionScheme.encryptWithKeyAlias(
            plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
        let cipheredHashedPppBase64 = cipheredHashedPpp.base64EncodedString()

        guard let plainPinData = pin.data(using: .utf8) else {
            Logger.security.error("Failed to encode poison pill pin as UTF-8 data")
            throw PinError.stringEncodingFailed
        }
        let cipheredPlainPpp = try await encryptionScheme.encryptWithKeyAlias(
            plain: plainPinData, keyAlias: Self.PIN_KEY_ALIAS)
        let cipheredPlainPppBase64 = cipheredPlainPpp.base64EncodedString()

        await dataSource.setPoisonPillPin(
            cipheredHashedPin: cipheredHashedPppBase64, cipheredPlainPin: cipheredPlainPppBase64
        )
    } catch {
        Logger.security.critical("Failed to set Poison Pill PIN", metadata: [
            "error": .string(String(describing: error))
        ])
    }
}
```

- [ ] **Step 3: Update existing repository tests**

In `SnapSafeTests/PinRepositoryTest.swift`, update `test_setAppPin_hashes_and_stores_ciphered_pin`:

```swift
func test_setAppPin_hashes_and_stores_ciphered_pin() async throws {
    let pin = "1234"
    let baseHashed = HashedPin(hash: "hash123", salt: "salt123")
    given(pinCrypto).hashPin(pin: .value(pin), deviceId: .value(deviceId)).willReturn(baseHashed)

    // The stored HashedPin includes pinType: .numeric
    var expectedStored = baseHashed
    expectedStored.pinType = .numeric
    let hashedData = try jsonEncoder().encode(expectedStored)
    let encryptedData = Data("encrypted".utf8)
    let expectedBase64 = encryptedData.base64EncodedString()

    given(encryptionScheme).encryptWithKeyAlias(
        plain: .value(hashedData), keyAlias: .value("pin_key")
    ).willReturn(encryptedData)

    given(settings).setAppPin(cipheredPin: .value(expectedBase64))
        .willReturn()

    await repo.setAppPin(pin, pinType: .numeric)

    verify(settings)
        .setAppPin(cipheredPin: .value(expectedBase64))
        .called(.once)
}
```

Update `test_setPoisonPillPin_stores_ciphered_hashed_and_plain` — change the final call:

```swift
await repo.setPoisonPillPin(ppp, pinType: .numeric)
```

(The rest of that test's setup and verification is unchanged — it stubs the encrypt calls and verifies `setPoisonPillPin(cipheredHashedPin:cipheredPlainPin:)` was called.)

Also update `test_activatePoisonPill_moves_ppp_and_removes_ppp` — `activatePoisonPill` calls no `set` methods directly, so no change needed there.

- [ ] **Step 4: Run repository tests**

In Xcode: **Product → Test** or run `PinRepositoryTests` specifically via the test navigator. Expected: all `PinRepositoryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Data/PIN/PinRepositoryImpl.swift SnapSafeTests/PinRepositoryTest.swift
git commit -m "feat: implement pinType storage in PinRepositoryImpl"
```

---

### Task 5: Update PinStrengthCheckUseCase with alphanumeric rules + tests

Write the failing tests first, then implement. `isPinStrongEnough` gains a `pinType` parameter (default `.numeric` for backward compat). Numeric logic is unchanged; alphanumeric skips digit-sequence checks and uses a common-password blacklist instead.

**Files:**
- Create: `SnapSafeTests/PinStrengthCheckUseCaseTests.swift`
- Modify: `SnapSafe/Data/UseCases/PinStrengthCheckUseCase.swift`

- [ ] **Step 1: Write failing tests**

Create `SnapSafeTests/PinStrengthCheckUseCaseTests.swift`:

```swift
// SnapSafeTests/PinStrengthCheckUseCaseTests.swift

import XCTest
@testable import SnapSafe

final class PinStrengthCheckUseCaseTests: XCTestCase {

    private var sut: PinStrengthCheckUseCase!

    override func setUp() {
        sut = PinStrengthCheckUseCase()
    }

    // MARK: - Numeric tests (existing behaviour preserved)

    func test_numeric_validPin_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("2847", pinType: .numeric))
        XCTAssertTrue(sut.isPinStrongEnough("739182", pinType: .numeric))
    }

    func test_numeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("123", pinType: .numeric))
    }

    func test_numeric_allSameDigits_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1111", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("999999", pinType: .numeric))
    }

    func test_numeric_ascendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1234", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("456789", pinType: .numeric))
    }

    func test_numeric_descendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("9876", pinType: .numeric))
    }

    func test_numeric_blacklist_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1212", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("6969", pinType: .numeric))
    }

    func test_numeric_containsLetters_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("12a4", pinType: .numeric))
    }

    // MARK: - Alphanumeric tests

    func test_alphanumeric_validMixed_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("ab92", pinType: .alphanumeric))
        XCTAssertTrue(sut.isPinStrongEnough("Tr0ub4", pinType: .alphanumeric))
    }

    func test_alphanumeric_lettersOnly_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("flux", pinType: .alphanumeric))
    }

    func test_alphanumeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("ab3", pinType: .alphanumeric))
    }

    func test_alphanumeric_allSameChar_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("aaaa", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("1111", pinType: .alphanumeric))
    }

    func test_alphanumeric_commonPassword_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("password", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("PASSWORD", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("letmein", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("abc123", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("qwerty", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("iloveyou", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("abcd1234", pinType: .alphanumeric))
    }

    // MARK: - Default pinType is numeric

    func test_defaultPinType_behavesAsNumeric() {
        XCTAssertTrue(sut.isPinStrongEnough("2847"))   // strong numeric
        XCTAssertFalse(sut.isPinStrongEnough("1234"))  // sequence
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

In Xcode: run `PinStrengthCheckUseCaseTests`. Expected: compile error — `isPinStrongEnough(_:pinType:)` doesn't exist yet.

- [ ] **Step 3: Implement updated PinStrengthCheckUseCase**

Replace the entire file:

```swift
// SnapSafe/Data/UseCases/PinStrengthCheckUseCase.swift

import Foundation

final class PinStrengthCheckUseCase {
    func isPinStrongEnough(_ pin: String, pinType: PINType = .numeric) -> Bool {
        switch pinType {
        case .numeric:
            return isNumericPinStrongEnough(pin)
        case .alphanumeric:
            return isAlphanumericPinStrongEnough(pin)
        }
    }

    private func isNumericPinStrongEnough(_ pin: String) -> Bool {
        guard pin.count >= 4, pin.allSatisfy({ $0.isNumber }) else {
            return false
        }

        if let firstChar = pin.first, pin.allSatisfy({ $0 == firstChar }) {
            return false
        }

        let digits = pin.compactMap { $0.wholeNumberValue }
        let isAscendingSequence = zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == 1 }
        let isDescendingSequence = zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == -1 }
        if isAscendingSequence || isDescendingSequence {
            return false
        }

        if Self.numericBlackList.contains(pin) {
            return false
        }

        return true
    }

    private func isAlphanumericPinStrongEnough(_ pin: String) -> Bool {
        guard pin.count >= 4 else { return false }

        if let firstChar = pin.first, pin.allSatisfy({ $0 == firstChar }) {
            return false
        }

        if Self.alphanumericBlackList.contains(pin.lowercased()) {
            return false
        }

        return true
    }

    private static let numericBlackList: [String] = [
        "1212",
        "6969",
    ]

    private static let alphanumericBlackList: [String] = [
        "password",
        "letmein",
        "abc123",
        "abcd1234",
        "qwerty",
        "iloveyou",
    ]
}
```

- [ ] **Step 4: Run tests to confirm they pass**

In Xcode: run `PinStrengthCheckUseCaseTests`. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Data/UseCases/PinStrengthCheckUseCase.swift SnapSafeTests/PinStrengthCheckUseCaseTests.swift
git commit -m "feat: add alphanumeric strength rules to PinStrengthCheckUseCase"
```

---

### Task 6: Update CreatePinUseCase

`createPin` accepts a `pinType: PINType` and passes it to `setAppPin`. The strength check also receives it. `PINSetupViewModel` calls this in Task 9.

**Files:**
- Modify: `SnapSafe/Data/UseCases/CreatePinUseCase.swift`

- [ ] **Step 1: Update createPin signature and body**

Replace the `createPin` method:

```swift
func createPin(_ pin: String, pinType: PINType = .numeric) async -> Bool {
    do {
        await pinRepository.setAppPin(pin, pinType: pinType)

        let hashedPin = await authorizePinUseCase.authorizePin(pin)
        guard let hashedPin else { return false }

        _ = await authorizationRepository.createKey(pin: pin, hashedPin: hashedPin)
        try await encryptionScheme.deriveAndCacheKey(plainPin: pin, hashedPin: hashedPin)
        await settingsDataSource.setIntroCompleted(true)
        return true
    } catch {
        Logger.security.error("Failed to create PIN", metadata: [
            "error": .string(String(describing: error))
        ])
        return false
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: success.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Data/UseCases/CreatePinUseCase.swift
git commit -m "feat: pass pinType through CreatePinUseCase"
```

---

### Task 7: Update CreatePoisonPillUseCase

Same treatment as Task 6 — `createPin(pppin:)` gains `pinType` and forwards it to `setPoisonPillPin`.

**Files:**
- Modify: `SnapSafe/Data/UseCases/CreatePoisonPillUseCase.swift`

- [ ] **Step 1: Update createPin signature and body**

Replace the `createPin` method:

```swift
func createPin(pppin: String, pinType: PINType = .numeric) async -> Bool {
    await pinRepository.setPoisonPillPin(pppin, pinType: pinType)
    guard let hashedPPPin = await pinRepository.getHashedPoisonPillPin() else {
        Logger.security.error("Failed to retrieve hashed poison pill pin")
        return false
    }

    do {
        try await encryptionScheme.createKey(plainPin: pppin, hashedPin: hashedPPPin)
    } catch {
        Logger.security.error("Failed to create poison pill key: \(error)")
        return false
    }

    return true
}
```

- [ ] **Step 2: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: success.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Data/UseCases/CreatePoisonPillUseCase.swift
git commit -m "feat: pass pinType through CreatePoisonPillUseCase"
```

---

### Task 8: Update PINEntryField

Add `pinType: PINType` parameter. Set `keyboardType` in `makeUIView` based on `pinType`, update it in `updateUIView` (needed because `pinType` arrives asynchronously from the ViewModel's `onAppear`). Update the character filter in `Coordinator.editingChanged`.

**Files:**
- Modify: `SnapSafe/Screens/PinVerification/PINEntryField.swift`

- [ ] **Step 1: Update PINEntryField struct and Coordinator**

Replace the `PINEntryField` struct (keep `PaddedSecureTextField` unchanged below it):

```swift
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
```

- [ ] **Step 2: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: errors at every `PINEntryField(...)` callsite that's missing `pinType:`. Fix those in the next tasks.

- [ ] **Step 3: Commit**

```bash
git add SnapSafe/Screens/PinVerification/PINEntryField.swift
git commit -m "feat: add pinType to PINEntryField for dynamic keyboard and character filter"
```

---

### Task 9: Update PINSetupViewModel and PINSetupView

Add `isAlphanumeric` toggle to the ViewModel. Update `validateAndFilterPIN` and `createPin` to use the type. Add the toggle UI above the PIN fields in the View.

**Files:**
- Modify: `SnapSafe/Screens/PinSetup/PINSetupViewModel.swift`
- Modify: `SnapSafe/Screens/PinSetup/PINSetupView.swift`

- [ ] **Step 1: Update PINSetupViewModel**

Replace the entire file:

```swift
// SnapSafe/Screens/PinSetup/PINSetupViewModel.swift

import Foundation
import FactoryKit

@MainActor
final class PINSetupViewModel: ObservableObject {

    @Injected(\.settingsDataSource)
    private var settings: SettingsDataSource

    // MARK: - Published Properties

    @Published var pin: String = "" {
        didSet {
            let filtered = validateAndFilterPIN(pin)
            if pin != filtered { pin = filtered }
        }
    }

    @Published var confirmPin: String = "" {
        didSet {
            let filtered = validateAndFilterPIN(confirmPin)
            if confirmPin != filtered { confirmPin = filtered }
        }
    }

    @Published var isAlphanumeric: Bool = false

    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // MARK: - Computed Properties

    var isPINValid: Bool {
        pin.count >= MIN_PIN_LENGTH && pin.count <= MAX_PIN_LENGTH
        && confirmPin.count >= MIN_PIN_LENGTH && confirmPin.count <= MAX_PIN_LENGTH
    }

    var canSubmit: Bool {
        isPINValid && !isLoading
    }

    // MARK: - Dependencies

    @Injected(\.createPinUseCase) private var createPinUseCase: CreatePinUseCase
    @Injected(\.pinStrengthCheckUseCase) private var pinStrengthCheckUseCase: PinStrengthCheckUseCase

    // MARK: - PIN Validation

    func validateAndFilterPIN(_ newValue: String) -> String {
        var filtered = newValue
        if isAlphanumeric {
            filtered = filtered.filter { $0.isLetter || $0.isNumber }
        } else {
            filtered = filtered.filter { $0.isNumber }
        }
        if filtered.count > MAX_PIN_LENGTH {
            filtered = String(filtered.prefix(MAX_PIN_LENGTH))
        }
        return filtered
    }

    // MARK: - Business Logic

    func createPin() async -> Bool {
        guard canSubmit else { return false }

        clearError()
        isLoading = true
        defer { isLoading = false }

        if pin != confirmPin {
            showError(message: "PINs do not match")
            return false
        }

        let pinType: PINType = isAlphanumeric ? .alphanumeric : .numeric

        if !isAlphanumeric {
            guard pin.allSatisfy({ $0.isNumber }) else {
                showError(message: "PIN must contain only numbers")
                return false
            }
        }

        if !pinStrengthCheckUseCase.isPinStrongEnough(pin, pinType: pinType) {
            showError(message: isAlphanumeric
                ? "PIN is too weak. Avoid common words and repeated characters."
                : "PIN is too weak. Avoid common patterns like 1234 or repeated digits.")
            return false
        }

        let success = await createPinUseCase.createPin(pin, pinType: pinType)

        if !success {
            showError(message: "Failed to create PIN. Please try again.")
            return false
        }

        await settings.setIntroCompleted(true)
        return true
    }

    // MARK: - Error Handling

    private func clearError() {
        showError = false
        errorMessage = ""
    }

    private func showError(message: String) {
        pin = ""
        confirmPin = ""
        errorMessage = message
        showError = true
    }

    func clearPinContent() {
        pin = ""
        confirmPin = ""
        clearError()
    }
}
```

- [ ] **Step 2: Update PINSetupView**

Replace the `VStack(spacing: 20)` block that contains the two `SecureField`s, adding the toggle above them. Also update the `keyboardType` to be dynamic. Replace the section from `VStack(spacing: 20) {` through its closing `}` and the `.animation` below it:

```swift
// SnapSafe/Screens/PinSetup/PINSetupView.swift
// Replace the inner VStack(spacing: 20) block and its .animation modifier:

VStack(spacing: 20) {
    Toggle(isOn: $viewModel.isAlphanumeric) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Use Alphanumeric PIN")
                .font(.subheadline)
            Text("Letters and numbers allowed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
    .disabled(!viewModel.pin.isEmpty || !viewModel.confirmPin.isEmpty)

    SecureField("Enter PIN", text: $viewModel.pin)
        .keyboardType(viewModel.isAlphanumeric ? .default : .numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
        .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))

    if !viewModel.pin.isEmpty && viewModel.pin.count < 6 {
        Text(PINStrings.shortPinWarning)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
            .transition(.opacity)
    }

    SecureField("Confirm PIN", text: $viewModel.confirmPin)
        .keyboardType(viewModel.isAlphanumeric ? .default : .numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
        .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
}
.animation(.snappy, value: !viewModel.pin.isEmpty && viewModel.pin.count < 6)
```

- [ ] **Step 3: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: success.

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Screens/PinSetup/PINSetupViewModel.swift SnapSafe/Screens/PinSetup/PINSetupView.swift
git commit -m "feat: add alphanumeric toggle to PIN setup"
```

---

### Task 10: Update PINVerificationViewModel and PINVerificationView

Load `pinType` from the stored `HashedPin` on appear. Expose it so the View can pass it to `PINEntryField`. Update the character filter in `updatePIN`. Fix the `PINEntryField` callsite to pass `pinType`.

**Files:**
- Modify: `SnapSafe/Screens/PinVerification/PINVerificationViewModel.swift`
- Modify: `SnapSafe/Screens/PinVerification/PINVerificationView.swift`

- [ ] **Step 1: Update PINVerificationViewModel**

Add `pinRepository` injection and `pinType` property. Add `updatePinType()` helper. Call it from `onAppear`. Update `updatePIN` filter.

Add these to the `// MARK: - Dependencies` section:

```swift
@Injected(\.pinRepository)
private var pinRepository: PinRepository
```

Add this published property alongside the others:

```swift
@Published var pinType: PINType = .numeric
```

Update `updatePIN` method:

```swift
func updatePIN(_ newValue: String) {
    var filteredValue = newValue
    if filteredValue.count > MAX_PIN_LENGTH {
        filteredValue = String(filteredValue.prefix(MAX_PIN_LENGTH))
    }
    switch pinType {
    case .numeric:
        filteredValue = filteredValue.filter { $0.isNumber }
    case .alphanumeric:
        filteredValue = filteredValue.filter { $0.isLetter || $0.isNumber }
    }
    pin = filteredValue
}
```

Update `onAppear` to also load the pin type:

```swift
func onAppear() {
    authorizationRepository.keepAliveSession()

    Task {
        await updateBackoffTime()
        await updateCurrentFailedAttempts()
        await updatePinType()
    }
}
```

Add private helper at the bottom of the `// MARK: - Private Methods` section:

```swift
private func updatePinType() async {
    guard let hashedPin = await pinRepository.getHashedPin() else { return }
    await MainActor.run { self.pinType = hashedPin.pinType }
}
```

- [ ] **Step 2: Update PINVerificationView — fix PINEntryField callsite**

In `PINVerificationView.swift`, the `PINEntryField` call currently lacks `pinType:`. Update it:

```swift
PINEntryField(
    text: $viewModel.pin,
    maxLength: MAX_PIN_LENGTH,
    isEnabled: !viewModel.isLoading,
    shouldFocus: shouldFocusField,
    pinType: viewModel.pinType
)
```

- [ ] **Step 3: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: success.

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Screens/PinVerification/PINVerificationViewModel.swift SnapSafe/Screens/PinVerification/PINVerificationView.swift
git commit -m "feat: load and apply pinType at PIN verification"
```

---

### Task 11: Update PoisonPillSetupWizardViewModel and PoisonPillPinCreationView

Add `isAlphanumeric` to the wizard ViewModel. Update `validateAndFilterPIN`, `setupPoisonPillPIN`, and the strength check call. Add the same toggle above the PIN fields in the creation view.

**Files:**
- Modify: `SnapSafe/Screens/PoisonPillSetup/PoisonPillSetupWizardViewModel.swift`
- Modify: `SnapSafe/Screens/PoisonPillSetup/PoisonPillPinCreationView.swift`

- [ ] **Step 1: Update PoisonPillSetupWizardViewModel**

Add `@Published var isAlphanumeric: Bool = false` alongside the other `@Published` properties.

Replace `validateAndFilterPIN`:

```swift
func validateAndFilterPIN(_ newValue: String) -> String {
    var filtered = newValue
    if isAlphanumeric {
        filtered = filtered.filter { $0.isLetter || $0.isNumber }
    } else {
        filtered = filtered.filter { $0.isNumber }
    }
    if filtered.count > MAX_PIN_LENGTH {
        filtered = String(filtered.prefix(MAX_PIN_LENGTH))
    }
    return filtered
}
```

Replace the `setupPoisonPillPIN` method:

```swift
func setupPoisonPillPIN() async -> Bool {
    guard canProceedFromPinCreation else { return false }

    isLoading = true
    showError = false

    let pinType: PINType = isAlphanumeric ? .alphanumeric : .numeric

    if !pinStrengthCheckUseCase.isPinStrongEnough(pin, pinType: pinType) {
        showError = true
        errorMessage = isAlphanumeric
            ? "PIN is too weak. Avoid common words and repeated characters."
            : "PIN is too weak. Avoid common patterns like 1234 or repeated digits."
        isLoading = false
        pin = ""
        confirmPin = ""
        return false
    }

    Logger.security.info("Setting up poison pill PIN")
    let success: Bool = await self.createPoisonPillUseCase.createPin(pppin: pin, pinType: pinType)

    isLoading = false

    if success {
        Logger.security.info("Poison pill PIN setup completed successfully")
        return true
    } else {
        showError = true
        errorMessage = "Failed to setup poison pill PIN"
        pin = ""
        confirmPin = ""
        Logger.security.error("Failed to setup poison pill PIN - createPinUseCase returned false")
        return false
    }
}
```

- [ ] **Step 2: Update PoisonPillPinCreationView — add toggle and dynamic keyboard**

In `PoisonPillPinCreationView.swift`, add `@Binding var isAlphanumeric: Bool` to the struct alongside the other stored properties. Then replace the entire `VStack(spacing: 20)` PIN input block (the one containing the two `SecureField`s) with this:

```swift
VStack(spacing: 20) {
    Toggle(isOn: $isAlphanumeric) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Use Alphanumeric PIN")
                .font(.subheadline)
            Text("Letters and numbers allowed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 50)
    .disabled(!pin.isEmpty || !confirmPin.isEmpty)

    SecureField("Enter new PIN", text: $pin)
        .keyboardType(isAlphanumeric ? .default : .numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .focused($focusedField, equals: .pin)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPinLengthValid(pin.count) ? Color.orange : Color.gray, lineWidth: 1)
        )
        .padding(.horizontal, 50)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
        .onChange(of: pin) { _, newValue in
            onPinChange(newValue)
        }

    if !pin.isEmpty && pin.count < 6 {
        Text(PINStrings.shortPinWarning)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 50)
            .transition(.opacity)
    }

    SecureField("Confirm PIN", text: $confirmPin)
        .keyboardType(isAlphanumeric ? .default : .numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .focused($focusedField, equals: .confirm)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPinLengthValid(confirmPin.count) ? Color.orange : Color.gray, lineWidth: 1)
        )
        .padding(.horizontal, 50)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
        .onChange(of: confirmPin) { _, newValue in
            onConfirmPinChange(newValue)
        }
}
.animation(.snappy, value: !pin.isEmpty && pin.count < 6)
```

In `PoisonPillSetupWizardView.swift`, update the `.pinCreation` case to pass the new binding:

```swift
case .pinCreation:
    PoisonPillPinCreationView(
        pin: $viewModel.pin,
        confirmPin: $viewModel.confirmPin,
        showError: $viewModel.showError,
        errorMessage: $viewModel.errorMessage,
        isLoading: $viewModel.isLoading,
        isAlphanumeric: $viewModel.isAlphanumeric,
        canProceed: viewModel.canProceedFromPinCreation,
        onPinChange: viewModel.updatePIN,
        onConfirmPinChange: viewModel.updateConfirmPIN,
        onSetup: {
            Task {
                let success = await viewModel.setupPoisonPillPIN()
                if success {
                    Logger.ui.info("Poison pill setup wizard completed successfully")
                    handleSuccess()
                }
            }
        },
        isPinLengthValid: viewModel.isPinLengthValid
    )
    .transition(.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    ))
```

Also update the `#Preview` at the bottom of `PoisonPillPinCreationView.swift`:

```swift
#Preview {
    @Previewable @State var pin = ""
    @Previewable @State var confirmPin = ""
    @Previewable @State var showError = false
    @Previewable @State var errorMessage = ""
    @Previewable @State var isLoading = false
    @Previewable @State var isAlphanumeric = false

    return NavigationStack {
        PoisonPillPinCreationView(
            pin: $pin,
            confirmPin: $confirmPin,
            showError: $showError,
            errorMessage: $errorMessage,
            isLoading: $isLoading,
            isAlphanumeric: $isAlphanumeric,
            canProceed: false,
            onPinChange: { _ in },
            onConfirmPinChange: { _ in },
            onSetup: {},
            isPinLengthValid: { length in length >= 4 && length <= 10 }
        )
    }
}
```

- [ ] **Step 3: Build to confirm no errors**

In Xcode: **Product → Build** (⌘B). Expected: success.

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Screens/PoisonPillSetup/PoisonPillSetupWizardViewModel.swift \
        SnapSafe/Screens/PoisonPillSetup/PoisonPillPinCreationView.swift
git commit -m "feat: add independent alphanumeric toggle to poison pill PIN setup"
```

---

### Task 12: Run full test suite and verify

- [ ] **Step 1: Run all unit tests**

In Xcode: **Product → Test** (⌘U). Expected: all tests in `SnapSafeTests` pass, including the new `PinStrengthCheckUseCaseTests` and the updated `PinRepositoryTests`.

- [ ] **Step 2: Manual smoke test — numeric PIN flow (regression check)**

1. Delete the app from simulator / reset state
2. Launch the app
3. Confirm the toggle is unchecked by default on the PIN setup screen
4. Enter a 6-digit numeric PIN, confirm it, tap "Set PIN"
5. Lock the app (background → foreground)
6. On the verification screen, confirm the number pad appears
7. Enter the PIN — confirm unlock succeeds

- [ ] **Step 3: Manual smoke test — alphanumeric PIN flow**

1. Delete the app from simulator / reset state
2. Launch the app
3. Check the "Use Alphanumeric PIN" toggle
4. Confirm the keyboard switches to the full keyboard
5. Try typing a symbol — confirm it's rejected
6. Enter a valid alphanumeric PIN (e.g., "flux92"), confirm it, tap "Set PIN"
7. Lock the app
8. On the verification screen, confirm the full keyboard appears
9. Enter the PIN — confirm unlock succeeds

- [ ] **Step 4: Manual smoke test — alphanumeric poison pill PIN**

1. With an existing PIN set, navigate to Settings → Poison Pill setup
2. Confirm the toggle defaults to unchecked
3. Check the toggle, enter an alphanumeric poison pill PIN
4. Confirm setup succeeds

- [ ] **Step 5: Final commit**

```bash
git commit --allow-empty -m "feat: alphanumeric PIN support complete"
```
