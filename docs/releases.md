# Build and release

This fork builds entirely from the repository and Apple SDKs. It does not resolve
Swift packages, install npm packages, use an app-update feed, or contact the
original project's website during build or release. GitHub Actions itself uses
pinned official checkout/artifact actions and GitHub's API.

## Automatic checks

Every branch push, pull request, and manual workflow run builds and runs the
macOS test target, then creates a universal (`arm64` and `x86_64`) Release app.
The `Build and release` workflow uses the GitHub-hosted `macos-15-intel` image and its
installed Xcode 26.3. Build ZIPs, SHA-256 checksums, and build metadata are retained
as the `Input-Source-Pro-macOS-universal` Actions artifact. Failed test runs also
retain their `.xcresult` bundle when available.

No signing certificates, Apple account, custom runner, or repository secrets are
required. The workflow's release job uses the automatic `GITHUB_TOKEN` with
`contents: write`; build jobs and pull requests only receive read access.
Repository settings must allow Actions and the official artifact actions.

## Version releases

Set the app target's `MARKETING_VERSION` consistently in Debug and Release, then
push the version commit to `main`. If that numeric version is newer than every
existing numeric version tag, CI automatically builds and tests the app, creates
the version tag at the tested commit, and publishes a GitHub Release with its ZIP
and checksum. The first version in a repository with no version tags also
publishes automatically. No release-note review or publication confirmation is
required. Ordinary commits using an existing version only produce build artifacts.

Optional release notes belong in `docs/release-notes/<version>.md` in the version
commit. CI uses that exact committed text and never calls a Markdown rendering
service. Missing notes do not block publication; an explicitly committed empty
notes file is rejected.

Explicit numeric version tags such as `2.15.0` or `v2.15.0` also trigger the same
build and publication process. The commit must belong to `main`; use only one
spelling per version. For this optional tag-driven route:

```sh
git tag 2.15.0
git push --atomic origin main refs/tags/2.15.0
```

Feature branches, pull requests, and manual workflow dispatches only build and
test. Tag versions override the app's marketing version in CI without modifying
source files. Build numbers are `1000 + git rev-list --count <commit>`, so full
Git history is required. The release target comes from `GITHUB_REPOSITORY`, not
the upstream repository. Publication jobs are serialized and main/version-tag
workflows are allowed to finish when another commit arrives.

The workflow first passes all tests and builds the universal app, verifies code
signatures, packaged helper files, bundle version, and absence of updater/custom
URL registration. It uploads these assets to a draft release:

- `Input-Source-Pro-<version>-macOS-universal.zip`
- `Input-Source-Pro-<version>-macOS-universal.zip.sha256`

The publisher verifies that the remote version tag points to the tested commit,
creating it only when absent. It never moves an existing tag. The draft is
published only after GitHub reports matching asset sizes and SHA-256 digests.
If publication fails, rerun the failed release job in the original Actions run:
the downloaded build metadata retains its release decision even if that attempt
already created the tag. Completed releases are never overwritten, and an
older/equivalent version cannot replace a newer published version. CI does not
edit repository files. Automatically created tags use `GITHUB_TOKEN`, so they do
not start a duplicate tag-push workflow.

## Signing and installation

Builds use ad-hoc signatures, not an Apple Developer ID certificate, and are not
notarized. macOS can require an explicit first-open approval. Native login-item
registration works on supported macOS versions when the app is installed in its
normal location; macOS 12 does not provide the native ServiceManagement API used
by this fork, so its login-item control is unavailable there.

The optional input-method cursor helper supports ad-hoc releases. Its native
local connection checks the current user, kernel process identity, executable
path, and a private listener session record; it does not require an Apple
certificate chain or matching Team ID. The helper's installed executable and
session files belong to the current user's trust boundary. Enhanced Mode,
Accessibility permission, and macOS input-method consent are still required.

## Local validation

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py'
xcodebuild -project 'Input Source Pro.xcodeproj' -scheme 'Input Source Pro' \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

Xcode and the macOS SDK are required to build/run the app. Python checks also run
on Linux, but do not validate macOS application behavior.
