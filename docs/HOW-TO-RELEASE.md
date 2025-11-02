# How to Release

- In XCode update the app version to a new SemVar value
- Commit and push all changes
- Tag the latest commit using the new SemVar value in the form of "v1.2.3"
- Push the tag, CI will now build and public that commit
