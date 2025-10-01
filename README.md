# SnapSafe for iOS

The camera app that minds its own business.

[![iOS build](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/ios.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/ios.yml)
[![CodeQL Advanced](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/d1016686e1f44d8fa5e6a2864ec6ac6b)](https://app.codacy.com/gh/SecureCamera/SecureCameraIos/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![Crowdin](https://badges.crowdin.net/snap-safe-android/localized.svg)](https://crowdin.com/project/snap-safe-android)

# Recommended iOS Settings

Apple provides a number of security features we can use on our devices to ensure the device is as secure as possible. This section outlines settings you can use to protect your device.

## USB-Restricted Mode (iOS 18+)

This option controls when the USB port is deactivated. By default, this should be in the most secure setting which is a setting of: **disabled**. This is important because it hardens the device from attacks via the USB port. The behavior of the USB port is dependent on the lock state of the device.

| Condition                          | What the port will do                                                                                |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Device has been unlocked < 1 h ago | Accept data from *known* accessories and hosts; prompt for “Trust This Computer” for new hosts       |
| Locked ≥ 1 h                       | New accessories are blocked until the user unlocks; previously-trusted ones still work for 30 days ➀ |
| No accessory use for ≥ 3 d         | The moment the device locks, *all* data connections are torn down; user must unlock to re-enable ➀   |


To check whether you have this setting disabled, go to:

```
Settings → Face ID & Passcode (or Touch ID & Passcode) → Allow Access When Locked → Accessories
```

Verify the setting is **disabled** (the default).

# Contributing

## Code Formatting
Use swiftformat to do this.

`swiftformat --swiftversion 6.0.3 .`

## Local Xcode Config

You're going to probably have your own team ID used in builds/provisioning. You can set that inside `Configs/LocalOverrides.xcconfig`. The contents of that file
should look something like this. Use your ID you see inside the .pbxproj file.

```
DEVELOPMENT_TEAM = AABBCC12345
```

Then to make sure this is included, do this in Xcode:

1. Click on the project.
2. Info > expand the Configuration section > Debug
3. Expand the debug section.
4. All targets are listed. At least set a config file for `SnapSafe` which is the main app local build.
5. In the column called `based on configuration file`, select the file `Configs/Signing.xcconfig`.

That should point to that local config and your value there will override whatever is in the signing or project-level config. This avoids the `.pbxproj` file shenanigans.
