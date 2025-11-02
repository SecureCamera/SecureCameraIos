# Development

## How to release a new version
Read the docs [here](HOW-TO-RELEASE.md)

## Running Fastlane

To run tests for a single version,

`bundle exec fastlane test`

To run the release tests, run all the same tests against more than just the latest supported version.

`bundle exec fastlane run_multi_version_tests`

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
