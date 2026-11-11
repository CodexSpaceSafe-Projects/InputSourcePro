# Input Source Pro — Offline Native Edition

A macOS input-source switcher built entirely with Apple frameworks. This fork
removes application Internet requests and all third-party Swift packages.

- Automatically choose input sources per application or browser website.
- Show a configurable input-source indicator near the cursor, mouse or window.
- Configure global keyboard and modifier shortcuts.
- Apply per-app punctuation and function-key modes.
- Import and export settings through the local settings window, with confirmation.

There is no startup telemetry, online feedback, advertising, in-app updater or
custom URL configuration import. Browser URLs are inspected locally for rules;
they are not requested or uploaded. The application uses local macOS IPC only.

## Build and test

Open `Input Source Pro.xcodeproj` in Xcode 26 or later, or run:

```sh
xcodebuild -project 'Input Source Pro.xcodeproj' -scheme 'Input Source Pro' \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/inputsourcepro-derived CODE_SIGNING_ALLOWED=NO test
```

No SwiftPM packages or third-party binaries need to be fetched. The app supports
macOS 12 and later; native launch-at-login registration requires macOS 13 or later.
Accessibility and Input Monitoring permissions are still required for the
features that inspect other applications or handle global input events.

The optional Cursor Helper requires the app and helper to have an Apple
publisher signature from the same developer. Ad-hoc CI builds disable that
optional integration rather than weaken IPC authentication; standard
Accessibility-based cursor tracking remains available.

## Automated builds and releases

Pushes and pull requests run tests and build a universal app. Push a version tag
such as `v2.14.0` or `2.14.0` to build and upload an app ZIP and SHA-256 checksum to
this repository's GitHub Releases. The pipeline uses GitHub-hosted macOS runners
and does not require signing credentials, npm, a third-party updater or a
release service. See [release instructions](docs/releases.md).

CI ZIPs are ad-hoc signed and are not notarized by Apple. macOS may require a
user-approved Gatekeeper exception; distributing Developer ID signed builds
requires a separate signing setup.

## Source and license

Based on Input Source Pro by runjuu and contributors. Existing source attributions
and license notices are retained. New wrappers use Apple Accessibility, Carbon,
Combine, Auto Layout, ServiceManagement and AppKit APIs directly.

Licensed under GPL-3.0; see [LICENSE](LICENSE).
