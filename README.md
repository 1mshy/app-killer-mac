# Killer

[![CI](https://github.com/1mshy/app-killer-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/1mshy/app-killer-mac/actions/workflows/ci.yml)

A native macOS utility for apps that won’t quit. Built with SwiftUI, AppKit, and a small libproc bridge. Requires macOS 26 or later. No dependencies or account.

## Run

```sh
./scripts/build.sh
open build/Killer.app
```

The build creates a locally ad-hoc-signed app at **build/Killer.app**. Drag it to Applications if desired. Open **Package.swift** in Xcode to work on the project. Running the bundled app is necessary for administrator actions because it includes the one-shot helper.

Local scripts prefer the installed Command Line Tools and a writable project cache. On the development machine, SDK 26.5 avoids the missing SwiftUI macro plugin in the CLT 27 SDK. CI uses its selected Xcode and matching SDK. Override `DEVELOPER_DIR` and `KILLER_SDK` for another installed Apple toolchain; an invalid explicit SDK fails rather than silently changing the toolchain. No Xcode license is accepted by the scripts.

## Use

- **Applications** includes normal and menu-bar apps.
- **Background** shows inspectable third-party helpers and command-line processes. Search covers names, executable paths, bundle identifiers, and PIDs.
- Select one process, choose **Force Quit**, and confirm. Unsaved work may be lost.
- **Force Quit as Administrator** invokes the standard macOS authorization prompt. Killer never reads or saves a password.
- **Recent activity** shows verified outcomes for this session; nothing is persisted.

Shortcuts: **⌘F** search, **⌘R** refresh, **⌘⌫** force quit selected process.

## What force quit means

Killer sends SIGKILL directly, so the target does not need to cooperate with Quit. It revalidates the exact PID, process start time, owner, and executable path immediately before signaling. It protects itself, its ancestors, and core operating-system processes. A signal being accepted is not treated as success: Killer verifies exit and watches for a replacement using the same executable for two seconds.

Apps such as FortiClient have separate UI, helper, and security processes. Stopping one does not stop all of them. A service can restart later, and administrator permission cannot override macOS or managed-app protection. Killer does not disable startup jobs, remove security software, modify system protection, or repeatedly stop a process. Choose a specific helper from Background, or use the app’s supported shutdown procedure. See [scope and primary references](docs/SCOPE.md).

The app is deliberately not sandboxed: controlling other processes requires it. The administrator helper runs once per explicit request and installs no service. The local build is ad-hoc signed, not Developer ID signed/notarized for public distribution. Kernel-level PID reuse between the final identity check and signal is a small unavoidable race in this public POSIX approach.

## Verify

```sh
./scripts/test.sh
./scripts/make-test-app.sh
open 'build/Killer Test App.app'
```

The disposable test app refuses normal Quit. Search for **Killer Test App** in Killer and force quit it to exercise the native UI. Automated tests use only child processes they create; they never terminate unrelated running apps. See [verification record](docs/VERIFICATION.md) for the checks performed on this machine.

## GitHub Actions

- **CI** runs on pull requests, pushes to `main`, and manual requests from the Actions tab. It checks shell/C syntax, runs all tests serially, builds and verifies the release app, then uploads a ZIP and SHA-256 checksum. Test/build/package steps have time limits; logs and an XML test report are retained even when a step fails. Artifacts expire after 14 days.
- **Release** runs when a `vMAJOR.MINOR.PATCH` tag is pushed. It repeats CI on that exact tag, embeds the version and workflow run number in the app, verifies the downloaded checksum, and publishes a GitHub Release with the app and generated change notes. A failed check blocks publication; an existing release is never silently overwritten.
- **Dependabot** proposes weekly updates to the pinned GitHub Actions dependencies.

The hosted build uses `macos-26`, Xcode 26.6, and Apple silicon (`arm64`). It requires no custom repository secrets: only the final release job receives the built-in token's `contents: write` permission. Pull requests use a read-only token. Tests only stop processes they create and do not request administrator credentials.

To publish a version after its changes reach `main`:

```sh
git tag -a v1.0.0 -m "Killer 1.0.0"
git push origin v1.0.0
```

Choose a new version for each release. Tags must contain three numeric components; prerelease suffixes are not currently supported. Find CI builds under [Actions](https://github.com/1mshy/app-killer-mac/actions) and published builds under [Releases](https://github.com/1mshy/app-killer-mac/releases).

Release ZIPs are **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper may block downloaded copies. This workflow packages the current local signing setup; it does not imply App Store or notarized distribution.

To reproduce versioned packaging locally:

```sh
KILLER_VERSION=1.0.0 KILLER_BUILD_NUMBER=1 ./scripts/build.sh
./scripts/package.sh
```

The ZIP and checksum are written to `build/artifacts/`. Packaging extracts the ZIP again and verifies executable permissions and signatures before declaring success.

## Structure

- `Sources/Killer`: SwiftUI interface, process listing, authorization, and verified outcomes.
- `Sources/KillerCore` and `Sources/CProcess`: process records, identity checks, and protected process policy.
- `Sources/KillerPrivileged`: one-shot authenticated helper; validates its arguments and target independently.
- `Tests`: core and operation tests plus the disposable macOS app fixture.
- `scripts`: reproducible app bundling, signing, icon generation, and test commands.
