# SnapSafe UI Tests & Screenshots

This directory contains UI tests for SnapSafe, including automated screenshot generation for the App Store.

## Overview

- **SnapSafeUITests.swift** - Basic UI tests that verify the app launches correctly
- **SnapSafeScreenshotTests.swift** - Comprehensive tests that navigate through the app and generate screenshots
- **SnapshotHelper.swift** - Fastlane snapshot integration (auto-generated)

## Running Screenshot Tests

### Option 1: Via Fastlane (Recommended for App Store)

```bash
cd /path/to/SnapSafe
bundle exec fastlane snapshot
```

This will:
- Run the UI tests on all devices configured in `Snapfile`
- Generate screenshots for all languages configured in `Snapfile`
- Save screenshots to `./screenshots/` directory
- Create organized folders by device and language

### Option 2: Via Xcode

1. Open `SnapSafe.xcworkspace`
2. Select the SnapSafe scheme
3. Press `Cmd+U` to run all tests
4. Or press `Cmd+6` to open Test Navigator and run specific tests

## How Screenshots Work

The screenshot system uses `fastlane snapshot` which:

1. **Launches your app** in a UI test
2. **Runs your UI tests** (from `SnapSafeScreenshotTests.swift`)
3. **Takes screenshots** when you call `snapshot("screenshot-name")`
4. **Organizes screenshots** by device size and language

### Taking Screenshots in Tests

```swift
@MainActor
func testGenerateScreenshots() throws {
    app.launch()

    // Navigate to a screen
    app.buttons["Settings"].tap()

    // Take a screenshot at this point
    snapshot("01-Settings-Screen")

    // Continue navigating...
}
```

## Screenshot Naming Convention

Screenshots are named with prefixes to ensure proper ordering:

- `01-Onboarding-Intro` - First screen users see
- `02-PIN-Setup` - PIN creation screen
- `03-PIN-Verification` - PIN entry screen
- `04-Camera-Main` - Main camera view
- `05-Camera-Ready` - Camera with controls visible
- `06-Gallery-View` - Photo gallery
- `07-Photo-Detail` - Single photo view
- `08-Settings-Main` - Settings screen
- `09-Settings-Security` - Security settings
- `10-About` - About screen

## Customizing Screenshots

### Edit Test Flow

Modify `SnapSafeScreenshotTests.swift` to change:
- Which screens are captured
- The order of navigation
- What actions are performed

### Add New Screenshots

```swift
// Navigate to your new screen
app.buttons["YourButton"].tap()
sleep(1)

// Take the screenshot
snapshot("11-Your-New-Screen")
```

### Configure Devices & Languages

Edit `fastlane/Snapfile`:

```ruby
devices([
  "iPhone 17",
  "iPhone 17 Pro Max",
  "iPad Pro 11-inch (M4)"
])

languages([
  "en-US",
  "es-ES",
  "fr-FR"
])
```

## UI Testing Launch Arguments

The app detects these launch arguments for testing:

- `-UITesting` - Enables UI testing mode
- `-SkipAuthentication` - Bypasses PIN entry for faster testing
- `-ResetOnboarding` - Resets onboarding state for testing intro screens

Configure these in your test's `setUp`:

```swift
app.launchArguments += ["-UITesting"]
app.launchArguments += ["-SkipAuthentication"]
```

## Handling Authentication in Tests

Since SnapSafe requires a PIN, you have two options:

### Option 1: Enter PIN in Test
```swift
private func enterTestPIN() {
    let pinField = app.secureTextFields.firstMatch
    pinField.tap()
    app.typeText("1234")
    app.buttons["Continue"].tap()
}
```

### Option 2: Bypass Authentication
Add logic in your app to skip authentication when `-SkipAuthentication` is set:

```swift
// In your ContentViewModel or AuthorizationRepository
if UITestingHelper.shouldSkipAuthentication {
    // Skip PIN verification
    authorizeSession()
}
```

## Troubleshooting

### Screenshots are blank or missing
- Make sure the UI elements are visible when `snapshot()` is called
- Add `sleep()` calls to wait for animations/transitions
- Check that element selectors match your actual UI

### Tests fail to navigate
- Use the Xcode Accessibility Inspector to find element identifiers
- Add `.accessibilityIdentifier()` to SwiftUI views for reliable selection
- Check if buttons/elements are actually visible and hittable

### Camera permission dialogs
- System permission dialogs can't be automated
- Pre-authorize camera access on simulators before running tests
- Or take screenshots that show the permission dialog as a feature

## Best Practices

1. **Use sleep() judiciously** - Wait for transitions, but not too long
2. **Test on clean state** - Reset simulator between test runs for consistency
3. **Use accessibility identifiers** - More reliable than text matching
4. **Test in multiple languages** - Ensure screenshots work for all locales
5. **Keep tests fast** - Minimize unnecessary navigation and delays

## App Store Requirements

For App Store screenshots, you need at least:
- **3-10 screenshots** per app size class
- **iPhone 6.7"** (iPhone 17 Pro Max)
- **iPhone 6.5"** (iPhone 14 Plus or 15 Plus)
- **iPad Pro 12.9"** (optional but recommended)

The screenshots must be:
- PNG or JPEG format
- RGB color space
- No transparency
- Correct dimensions for each device size

Fastlane snapshot handles all of this automatically!
