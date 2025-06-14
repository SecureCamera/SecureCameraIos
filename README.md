# SnapSafe for iOS

The camera app that minds its own business.

[![iOS build](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/ios.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/ios.yml)
[![CodeQL Advanced](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml)


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
