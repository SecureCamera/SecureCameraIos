# Alphanumeric PIN Support

**Date:** 2026-06-15  
**Branch:** video  
**Status:** Approved

## Overview

Users can opt into an alphanumeric PIN (letters + numbers, no symbols) at setup time via a toggle. The default remains numeric-only. The main PIN and the Poison Pill PIN can each be independently numeric or alphanumeric. Once a PIN is set, its type is fixed — users cannot switch between numeric and alphanumeric without resetting their PIN.

The design mirrors the Android app's architecture patterns (ViewModel → UseCase → Repository) to keep both platforms consistent.

## Constraints

- Same length limits as numeric PINs: 4–10 characters
- Alphanumeric allows `isLetter || isNumber` only — no symbols or whitespace
- Toggle is default-off (numeric is the default)
- PIN type is immutable once set
- Main PIN type and Poison Pill PIN type are independent
- Backward-compatible: existing numeric-only PINs decode without migration

## Data Layer

### New: `PINType` enum

New file `SnapSafe/Data/PIN/PINType.swift`:

```swift
enum PINType: String, Codable, Sendable {
    case numeric
    case alphanumeric
}
```

### `HashedPin` — add `pinType`

`HashedPin` gains a `pinType` field with a `.numeric` default. Since `HashedPin` is `Codable`, existing stored values decode cleanly — any stored `HashedPin` without a `pinType` key decodes as `.numeric`.

```swift
struct HashedPin: Codable, Equatable, Sendable {
    let hash: String
    let salt: String
    var pinType: PINType = .numeric
}
```

The PIN type is co-located with the hash and salt — they are stored and retrieved together, so type and credential can never drift out of sync.

### `PinRepository` protocol changes

Two method signatures gain a `pinType` parameter:

```swift
func setAppPin(_ pin: String, pinType: PINType) async
func setPoisonPillPin(_ pin: String, pinType: PINType) async
```

`PinRepositoryImpl` implements both by embedding `pinType` into the `HashedPin` before storage.

### Use case changes

- `CreatePinUseCase.createPin(_:pinType:)` — accepts `PINType`, passes it to `setAppPin`
- `CreatePoisonPillUseCase` — same treatment for `setPoisonPillPin`

## Strength Checking

`PinStrengthCheckUseCase.isPinStrongEnough(_:pinType:)` gains a `pinType` parameter.

**Numeric** (existing logic, unchanged):
1. All characters must be digits
2. No all-same-digit pattern (e.g., `"1111"`)
3. No ascending/descending digit sequence (e.g., `"1234"`, `"9876"`)
4. Not in numeric blacklist (`"1212"`, `"6969"`)

**Alphanumeric** (new logic):
1. Skip digit-only and sequence checks
2. Keep all-same-character check (e.g., `"aaaa"`)
3. Common-password blacklist: `"password"`, `"letmein"`, `"abc123"`, `"abcd1234"`, `"qwerty"`, `"iloveyou"`

## Setup UX — Main PIN

### `PINSetupViewModel` (Screens/PinSetup/)

- Add `@Published var isAlphanumeric: Bool = false`
- `validateAndFilterPIN` filters `\.isNumber` when `false`, `{ $0.isLetter || $0.isNumber }` when `true`
- `createPin()` passes `isAlphanumeric ? .alphanumeric : .numeric` to `CreatePinUseCase`
- The digits-only guard in `createPin()` is replaced with a type-aware check

### `PINSetupView`

A `Toggle` row is inserted above the two `SecureField`s:

```
[ Use Alphanumeric PIN (letters & numbers)  ◯ ]
[ Enter PIN field                               ]
[ Confirm PIN field                             ]
```

- Toggle is bound to `viewModel.isAlphanumeric`
- Both `SecureField`s switch `.keyboardType` between `.numberPad` (off) and `.default` (on) based on the toggle
- The short-PIN warning copy ("6+ characters") already applies to both types — no change needed
- The toggle is disabled once either PIN field is non-empty, preventing mid-entry type switching

## Setup UX — Poison Pill PIN

`PoisonPillSetupWizardViewModel` gains `@Published var isAlphanumeric: Bool = false` independently from the main PIN.

`PoisonPillPinCreationView` gets the same `Toggle` treatment above its two `SecureField`s. The toggle binds to the wizard ViewModel's `isAlphanumeric` and the keyboard type switches identically.

## Verification UX

### `PINVerificationViewModel`

- Add `@Published var pinType: PINType = .numeric`
- In `onAppear`, after loading `HashedPin`, set `self.pinType = hashedPin.pinType`
- `updatePIN` uses `pinType` to determine the allowed character set

### `PINVerificationView`

Passes `viewModel.pinType` down to `PINEntryField`.

### `PINEntryField`

Gains a `pinType: PINType` parameter (alongside the existing `maxLength`, `isEnabled`, `shouldFocus`):

- `keyboardType` in `makeUIView`: `.numberPad` for `.numeric`, `.default` for `.alphanumeric`
- `Coordinator.editingChanged` filter:  
  - Numeric: `raw.filter(\.isNumber)`  
  - Alphanumeric: `raw.filter { $0.isLetter || $0.isNumber }`

## Files Changed

| File | Change |
|---|---|
| `Data/PIN/PINType.swift` *(new)* | `PINType` enum |
| `Data/PIN/HashedPin.swift` | Add `pinType: PINType = .numeric` |
| `Data/PIN/PinRepository.swift` | Add `pinType` param to `setAppPin`, `setPoisonPillPin`; length constants unchanged |
| `Data/PIN/PinRepositoryImpl.swift` | Implement updated signatures |
| `Data/UseCases/CreatePinUseCase.swift` | Accept and pass `pinType` |
| `Data/UseCases/CreatePoisonPillUseCase.swift` | Accept and pass `pinType` |
| `Data/UseCases/PinStrengthCheckUseCase.swift` | Add `pinType` param, alphanumeric strength rules |
| `Screens/PinVerification/PINEntryField.swift` | Add `pinType` param, dynamic keyboard + filter |
| `Screens/PinSetup/PINSetupView.swift` | Toggle above fields, dynamic keyboard type |
| `Screens/PinSetup/PINSetupViewModel.swift` | `isAlphanumeric`, updated validation + `createPin` (note: `ViewModels/PINSetupViewModel.swift` is a legacy duplicate — not changed) |
| `Screens/PinVerification/PINVerificationView.swift` | Pass `pinType` to `PINEntryField` |
| `Screens/PinVerification/PINVerificationViewModel.swift` | Load + expose `pinType` |
| `Screens/PoisonPillSetup/PoisonPillPinCreationView.swift` | Toggle above fields, dynamic keyboard |
| `Screens/PoisonPillSetup/PoisonPillSetupWizardViewModel.swift` | `isAlphanumeric` flag |

## Out of Scope

- Changing minimum/maximum length for alphanumeric PINs
- Allowing symbols or whitespace
- Letting users change PIN type after initial setup (requires re-creating the PIN)
- Password strength meter UI
- Migrating existing users to alphanumeric
