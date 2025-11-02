# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands
- Open project: `open "SnapSafe/SnapSafe.xcodeproj"`
- Build: `xcodebuild -project "SnapSafe/SnapSafe.xcodeproj" -scheme "SnapSafe" build`
- Run tests: `xcodebuild -project "SnapSafe/SnapSafe.xcodeproj" -scheme "SnapSafe" test`
- Run single test: `xcodebuild -project "SnapSafe/SnapSafe.xcodeproj" -scheme "SnapSafe" test -only-testing:SnapSafeTests/SnapSafeTests/testName`
- Do not automatically run code formatting commands.

## Code Style Guidelines
- **Imports**: Order imports alphabetically starting with system imports (SwiftUI, Foundation, etc.) followed by local modules
- **Formatting**: 4-space indentation, lines under 120 characters.
- **Naming**: Use camelCase for variables/functions, PascalCase for types, use descriptive names
- **Access Control**: Always specify access level (private, internal, public)
- **Error Handling**: Use try/catch for critical operations, prefer optional chaining when appropriate
- **Comments**: Add comments for complex logic and security-related operations, but not for obvious code. Never use emojis in code or comments.
- **Security**: Never log sensitive info, always use Secure Enclave for crypto keys, handle user authentication safely

## Architecture
- SwiftUI for UI components
- MVVM pattern
- Files ending with `Repository` handle specific security domains (AuthRepository, PINRepository, etc.)
- Keep containers at the edge. Whether it’s environment or withDependencies, wire everything in @main or your test helper, never deep inside features.
- Prefer initializer injection in view-models. This keeps them platform-agnostic and easy to preview.
- Use protocols only where you truly need substitution. Concrete types everywhere else keep the call-graph easier to navigate.
- Use async-friendly APIs from day one. Return async throws rather than completion handlers so your DI layer doesn’t block future concurrency refactors.
- use swift's EnvironmentValues
- refactor opportunity - Define a protocol, give it a live + mock implementation, wire it once in the root scene, and pull it from any view or view-model.
- The application has distinct layers: The UI View, the view model, use cases, repositories, data sources.
- The UI view should only have swiftUI with UI-only logic.
- The view model should have logic limited to validation of input and UI logic. The UI calls use cases.
- The use cases expose a single function, that function using one or more repos. A use case encapsulates a single piece of business logic.
- The repository is for a specific area of the product. It contains the majority of the logic.
- Data sources are stateless. They have getters and setters only.

## guidelines
Create unit tests for functionality added or changed in this codebase.
When writing messages in test case assertions, include values being compared during the failed assertion. This helps debugging.

## TODOs
If I ask to address each of the TODO items, go read the file TODOS.md to find a current list of issues to resolve.
