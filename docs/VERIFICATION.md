# Verification

Verified on the development Mac on September 18, 2026. Only intentionally created test processes were force-quit. FortiClient and the user’s unrelated apps were not stopped.

## Automated checks passed

The complete test run passed **6 core test definitions and 10 app test definitions**. The app suite includes a parameterized quoting test with **10 input cases**.

Core checks cover process discovery and stable identity, protected-process rules, already-exited targets, refusal to stop Killer itself, exact termination of a disposable process that ignores SIGTERM, and detection of an exited child that remains an unreaped zombie. Stale birth time, changed executable path, and changed owner are rejected before signaling the live fixture.

App checks cover:

- An owned process that ignores ordinary termination is force-quit, and its actual exit is verified.
- An existing process using the same executable is left running and is not incorrectly classified as a restart.
- A new replacement process is detected, reported, and left running.
- Already-exited and stale targets produce the appropriate outcomes without stopping their replacements.
- Protected targets and a missing administrator helper are handled without sending a termination request.
- Refresh removes an expired selection, and search finds an owned background process.
- Shell and AppleScript quoting preserve empty strings, spaces, single and double quotes, backslashes, shell substitution text, control characters, and Unicode. The test runs real shell and AppleScript round trips without requesting administrator privileges. Foundation’s canonical Unicode normalization is accounted for.

The administrator executable was separately checked with **18 malformed argument cases**, including missing and extra arguments, invalid signs/digits, numeric overflow, invalid timestamp fields, invalid owner IDs, and nonabsolute paths. Every case returned exit code 64 with valid version-1 `invalidArguments` JSON. A valid invocation without administrator privileges returned exit code 77 with `authorizationRequired` JSON. These checks sent no termination signal and showed no administrator prompt.

The tests compile small C fixtures that ignore SIGTERM and announce readiness. They do not copy or terminate installed applications. An earlier fixture based on copied Apple binaries was replaced because macOS killed those copies before the tests could initialize them.

## Native interface smoke test passed

The debug app bundle was exercised through the macOS interface against a deliberately launched native **StubbornApp** fixture:

1. The fixture survived Command-Q, confirming that ordinary Quit was refused.
2. Killer search located the fixture.
3. Cancelling the force-quit confirmation left the fixture running.
4. Confirming Force Quit terminated the fixture.
5. Killer reported **Stopped** and recorded the result in **Recent activity**.

The interface check found that Command-F did not focus the SwiftUI toolbar text field. The final implementation uses a native AppKit search field with explicit first-responder routing. Subsequent interface changes hide protected operating-system rows, classify nested application helpers as background processes, and constrain the process-list width. After those changes, the focused `AppModelTests` run passed **2 tests** covering protected selection, background search, refresh, and stale-selection removal.

The final signed release bundle was then launched and verified through its native interface:

- Command-F focused the native search field; typing filtered the list immediately.
- Searching for a different process cleared the previous hidden selection.
- Command-Delete opened the confirmation for the selected disposable app.
- Confirming Force Quit stopped that app and displayed the verified **Stopped** result.
- The application list omitted protected system services and the inspector layout remained readable.
- Searching **Forti** in Background found the installed FortiClientAgent, FortiTray, FctMiscAgent, and a matching executable path for CredentialStore. These real processes were only inspected, never terminated.

The final app was left open. Both disposable native test-app instances were stopped during the smoke tests.

## Toolchain and reproduction

Run the repository test script from the project directory:

```sh
./scripts/test.sh
```

The script configures the available Apple Command Line Tools, writable project-local caches, the installed macOS 26.5 SDK, and explicit Swift Testing macro-plugin loading where needed. The app targets macOS 26 or newer. This avoids the unavailable SwiftUI macro plugin in the development machine’s newer SDK and does not accept or modify an Xcode license agreement.

Run process-control integration tests outside an agent execution sandbox that blocks child-process inspection or AppleScript execution. The verified run used the host execution environment with sandbox escalation approved; it did not run as the root user.

For the focused model checks after interface filtering changes:

```sh
./scripts/test.sh --filter AppModelTests
```

## Remaining verification boundaries

- The successful administrator-authorization path has **not been exercised**: completing the macOS prompt requires the user’s administrator credentials. Argument validation, unprivileged refusal, missing-helper behavior, and the quoting used to construct that request were checked.
- No claim is made that this app can stop protected or centrally managed FortiClient services. macOS or the product’s management policy may refuse termination, and services can relaunch processes.
- The final release build passed. Ad hoc signature verification with `codesign --verify --deep --strict` passed for the app and helper, and the app’s property-list lint passed. Both debug and final release bundles passed native interface smoke tests.
- Signing for distribution and notarization require the developer’s own signing identity. Local build verification does not establish Gatekeeper acceptance on a different Mac.
