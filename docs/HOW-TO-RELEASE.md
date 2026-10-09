# How to Release

Pushing a `v*` tag triggers `.github/workflows/publish-release.yml`, which:

1. Builds the IPA (`fastlane build_release`) and publishes a GitHub Release with it attached.
   Publishing that release triggers `notify-release.yml`, which posts to Discord immediately.
2. Rebuilds and uploads to App Store Connect (`fastlane deploy`).
   It does **not** upload metadata or screenshots and does **not** submit for review.

## 1. Before merging

- [ ] Pick the new SemVer version (e.g. `1.4.0`).
- [ ] Run the full test suite on a **physical device**. The Secure Enclave and file-protection tests
      (`HardwareEncryptionScheme*Tests`, `FileBasedSettingsDataSourceProtectionTests`) are skipped on the simulator.
- [ ] Run an App Store review readiness pass (the `appstore-review` Claude skill) on new features.

## 2. Bump the version (on the feature branch)

- [ ] In Xcode, set the SnapSafe target's Version (`MARKETING_VERSION`) to the new value.
- [ ] Leave Build (`CURRENT_PROJECT_VERSION`) at `1` unless re-uploading the same version (see Gotchas).
- [ ] Commit and push.

## 3. Merge to main

- [ ] Open a PR into `main` and wait for the "iOS Build and Test" check to pass (unit tests only).
- [ ] Merge, then update local `main`:

```bash
git checkout main && git pull
```

## 4. Tag (this starts the release)

Tag the merge commit on `main`, not the feature branch:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

- [ ] Watch the "Publish iOS Release" workflow; both jobs must succeed.

## 5. App Store Connect (manual)

- [ ] Wait for the build to finish processing.
- [ ] Answer the export compliance question for the build. SnapSafe declares non-exempt encryption
      (`ITSAppUsesNonExemptEncryption` in `Snap-Safe-Info.plist`) and has no `ITSEncryptionExportComplianceCode`,
      so App Store Connect asks for every build.
- [ ] Create the new version, enter "What's New" release notes, and select the build.
- [ ] Update screenshots if the UI changed.
- [ ] Submit for review; release once approved.

## Gotchas

- **Discord fires before the App Store upload.** The notification goes out when the GitHub Release is
  published at the end of job 1, even if job 2 later fails.
- **Retries need a new build number.** If job 2 fails after uploading, App Store Connect rejects a re-upload
  with the same build number. Bump `CURRENT_PROJECT_VERSION` before retrying.
- **Re-pushing a tag duplicates the release.** Deleting and re-pushing a tag creates another GitHub Release
  and another Discord post.
- **CI pins its Xcode version** (`xcode-select` step in the workflows). The shipped binary is built with that
  toolchain, not your local Xcode.
