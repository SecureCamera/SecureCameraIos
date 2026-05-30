# SnapSafe for iOS

The camera app that minds its own business.

[![iOS build](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/build-and-test.yml)
[![CodeQL Advanced](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml/badge.svg)](https://github.com/SecureCamera/SecureCameraIos/actions/workflows/codeql.yml)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/d1016686e1f44d8fa5e6a2864ec6ac6b)](https://app.codacy.com/gh/SecureCamera/SecureCameraIos/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![Crowdin](https://badges.crowdin.net/snap-safe-ios/localized.svg)](https://crowdin.com/project/snap-safe-ios)

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

# Building, Testing & Releasing

The build, test, and release pipeline is driven by [fastlane](https://fastlane.tools).
Everything runs through `bundle exec fastlane <lane>`, so install the Ruby
dependencies once:

```bash
bundle install
```

## Fastlane lanes

| Lane | What it does |
| ---- | ------------ |
| `fastlane build` | Compiles the app *for testing* (`build_for_testing`). |
| `fastlane test` | Runs the `SnapSafeTests` unit suite on an iPhone simulator. |
| `fastlane run_multi_version_tests` | Runs the unit suite across multiple iOS versions (18.5 and 26.0). |
| `fastlane verify_test_membership` | Runs the test-target membership guard on its own (see below). |
| `fastlane build_release` | Builds a signed App Store IPA into `./build` (`gym`). |
| `fastlane beta` | Builds and uploads to TestFlight. |
| `fastlane deploy` | Builds and uploads to App Store Connect. |

Common settings live in `fastlane/Scanfile` (test config), `fastlane/Snapfile`
(screenshots), and `fastlane/Appfile` (app identifier).

## Test-target membership guard

Test files in Xcode must be explicitly added to the `SnapSafeTests` target. A
`.swift` file that exists on disk but isn't a member is silently never compiled —
its tests never run, while the test bundle still reports success. To prevent this,
`scripts/check_test_target_membership.rb` fails if any `.swift` file under
`SnapSafeTests/` is not compiled by the target.

The `build` and `test` lanes run this guard **first**, so it is enforced both
locally and in CI (CI runs `fastlane test`). Run it directly with:

```bash
bundle exec fastlane verify_test_membership
# or:
bundle exec ruby scripts/check_test_target_membership.rb
```

On failure it lists the offending files; add each to the `SnapSafeTests` target
(Xcode → File Inspector → Target Membership) and re-run.

## Continuous integration

| Workflow | Trigger | Does |
| -------- | ------- | ---- |
| `.github/workflows/build-and-test.yml` | push / PR to `main` | `fastlane test` (membership guard + unit tests), publishes results. |
| `.github/workflows/codeql.yml` | push / PR / schedule | CodeQL security analysis. |
| `.github/workflows/publish-release.yml` | push of a `v*` tag | `fastlane build_release` → GitHub Release, then `fastlane deploy` → App Store Connect. |
| `.github/workflows/notify-release.yml` | GitHub release published | Sends a release notification. |

## Cutting a release

1. Make sure `main` is green (the build-and-test workflow passes).
2. Tag the release commit and push the tag:

   ```bash
   git tag v1.3.0
   git push origin v1.3.0
   ```

3. The `Publish iOS Release` workflow builds the IPA, creates the GitHub Release,
   and uploads the build to App Store Connect.

Release signing/upload requires the repository secrets used by the workflow:
the distribution certificate/profile import, and the App Store Connect API key
(`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_CONTENT`).

# Contributing

Take a look at our [development](docs/DEVELOPMENT.md) docs.
