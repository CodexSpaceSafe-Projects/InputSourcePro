# Build and release

This fork builds entirely from the repository and Apple SDKs. It does not resolve
Swift packages, install npm packages, use an app-update feed, or contact the
original project's website during build or release. GitHub Actions itself uses
pinned official checkout/artifact actions and GitHub's API.

## Automatic checks

Every branch push, pull request, and manual workflow run builds and runs the
macOS test target, then creates a universal (`arm64` and `x86_64`) Release app.
The `Build and release` workflow uses the GitHub-hosted `macos-15` image and its
installed Xcode 26.3. Build ZIPs, SHA-256 checksums, and build metadata are retained
as the `Input-Source-Pro-macOS-universal` Actions artifact. Failed test runs also
retain their `.xcresult` bundle when available.

No signing certificates, Apple account, custom runner, or repository secrets are
required. The workflow's release job uses the automatic `GITHUB_TOKEN` with
`contents: write`; ordinary builds and pull requests only receive read access.
Repository settings must allow Actions and the official artifact actions.

## Version releases

Push a numeric version tag such as `2.14.0` or `v2.14.0` to publish a release.
The release commit must already belong to `main`; use only one spelling per
version. A version change in Xcode alone builds a branch artifact, but does not
publish a release. Tag versions override the app's marketing version in CI
without modifying source files. Build numbers are `1000 + git rev-list --count
<commit>`, so full Git history is required.

Before adding or editing release notes or publishing a version, follow the
changelog review requirements in `AGENTS.md`. Save approved notes in
`docs/release-notes/<version>.md` before tagging. The workflow uses that exact
committed text when present, and never generates a changelog or calls a Markdown
rendering service. If no version notes file exists, the release body is empty.
An empty notes file is rejected.

After the changes and wording have been reviewed, push the branch and version
tag atomically, for example:

```sh
git tag 2.14.0
git push --atomic origin main refs/tags/2.14.0
```

Only the tag event publishes a GitHub Release. Branch events never create beta
releases. The release target is the repository running the workflow, obtained
from `GITHUB_REPOSITORY`; it is not hardcoded to the upstream repository.

The workflow first passes all tests and builds the universal app, verifies code
signatures, packaged helper files, bundle version, and absence of updater/custom
URL registration. It uploads these assets to a draft release:

- `Input-Source-Pro-<version>-macOS-universal.zip`
- `Input-Source-Pro-<version>-macOS-universal.zip.sha256`

The draft is published only after GitHub reports matching asset sizes and
SHA-256 digests. Failed draft uploads can be retried. Completed releases are never
overwritten, and an older/equivalent version cannot replace a newer published
version. The workflow does not edit tags or repository files.

## Signing and installation

Builds use ad-hoc signatures, not an Apple Developer ID certificate, and are not
notarized. macOS can require an explicit first-open approval. Native login-item
registration works on supported macOS versions when the app is installed in its
normal location; macOS 12 does not provide the native ServiceManagement API used
by this fork, so its login-item control is unavailable there.

The optional input-method cursor helper requires a trusted team signing identity
for its authenticated connection. Ad-hoc releases intentionally leave that
optional helper unavailable; the app reports the limitation, and standard
Accessibility-based cursor placement remains available. This avoids weakening
local IPC authentication for unsigned builds.

## Local validation

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py'
xcodebuild -project 'Input Source Pro.xcodeproj' -scheme 'Input Source Pro' \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

Xcode and the macOS SDK are required to build/run the app. Python checks also run
on Linux, but do not validate macOS application behavior.
