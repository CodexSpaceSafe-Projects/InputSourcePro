# Repository Guidelines

## Project Structure & Module Organization
- `Input Source Pro.xcodeproj` is the Xcode project; open it to build and run.
- `Input Source Pro/` holds the app source code.
  - `Controllers/`, `Models/`, `Persistence/`, `System/`, `UI/`, `Utilities/`, `Window/` group the core logic and UI.
  - `Resources/` contains `Info.plist`, `Signing.entitlements`, localized strings (`*.lproj`), and assets in `Resources/Assets.xcassets`.
  - `Preview Content/` includes SwiftUI preview assets.
- `imgs/` is used for README media.

## Build, Test, and Development Commands
- Open `Input Source Pro.xcodeproj` in Xcode and use:
  - `Cmd+B` to build, `Cmd+R` to run, `Cmd+U` to run tests.
- CLI builds use the shared scheme name:
  - `xcodebuild -scheme "Input Source Pro" -configuration Debug build`
  - `xcodebuild -scheme "Input Source Pro" -configuration Debug test`

## Coding Style & Naming Conventions
- Swift-only codebase; follow Swift API Design Guidelines and existing conventions.
- Indentation is 4 spaces; keep declarations and SwiftUI views formatted like nearby files.
- Naming:
  - Types use `UpperCamelCase` (e.g., `IndicatorWindowController`).
  - Files follow type names, and extensions use `Type+Feature.swift` (e.g., `IndicatorWindowController+Activation.swift`).
- No repo-wide formatter or linter config is present; do not introduce reformatting-only diffs.

## Testing Guidelines
- The Xcode scheme includes a `Tests` target; add new tests there as `*Tests.swift` using XCTest.
- This fork uses Apple frameworks only. Do not reintroduce SwiftPM packages, application Internet requests, telemetry, in-app updates, or custom URL import handlers. Use Xcode 26 or later. Native login-item registration requires macOS 13; the app still supports macOS 12.
- If you add tests, ensure they run via `Cmd+U` or `xcodebuild test` before opening a PR.

## Commit & Pull Request Guidelines
- Commit messages follow conventional commits with optional scopes, e.g., `feat(UI): add indicator toggle` or `fix: handle nil input source`.
- Branch names are descriptive and prefixed (e.g., `feature/add-xyz-support`, `fix/indicator-crash`).
- PRs should include: purpose, linked issues (e.g., `Closes #123`), summary of changes, and testing notes. Add screenshots or screen recordings for UI changes.

## Automatic Releases
- New versions build and publish to this repository's GitHub Releases automatically after tests and bundle checks pass. Do not ask for release-note wording approval or separate publication confirmation when the user has requested a new version or release.
- Set the app's `MARKETING_VERSION` to the new numeric version and push to `main`. CI creates the matching version tag and uploads the universal ZIP and SHA-256 checksum. Explicit numeric version tag pushes also publish releases. Ordinary commits for an existing version do not publish another release.
- Release notes are optional. When writing them, save `docs/release-notes/<version>.md` with the version commit, describe changes since the preceding stable release, and use verified contributor names and relevant pull request links. Missing notes never block publication.
- Preserve published releases and their assets; use a new version for subsequent changes. See `docs/releases.md` for automation and retry behavior. Release builds use ad-hoc signatures; Developer ID signing is a separate setup.
