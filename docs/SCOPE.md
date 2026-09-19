# Killer scope

Killer is a native macOS utility for stopping apps and their explicitly selected processes when normal Quit does not work. It uses SwiftUI for the interface and AppKit plus native process APIs for discovery and termination. The deployment target follows the installed modern macOS SDK; backward compatibility is outside this project’s scope.

## Included behavior

- Search running apps, including accessory and menu-bar apps, and inspect the exact process name, owner, executable, and PID before acting.
- Force quit an explicitly selected process. Bind the selection to its PID and process start time, and recheck its owner and executable immediately before termination.
- Show truthful outcomes: stopped, already stopped, identity changed, permission denied, still running, or restarted. A successfully sent signal does not itself prove termination.
- Offer a one-time administrator authorization when a selected eligible third-party process needs it. The helper exits after one request and installs no persistent service.
- Refuse core system/session processes and the running Killer app. Avoid loose process-name matching or broad kill commands.
- Explain possible loss of unsaved work as part of the force-quit action. Do not automatically repeat termination when an app restarts.
- Provide keyboard search and navigation, useful empty states, and native light/dark appearance.

## Explicit limits

Force quitting an app does not disable its login item, uninstall it, or stop every separately installed service. FortiClient has distinct GUI, agent, controller, VPN, and security processes. Its GUI disappearing is not proof that its VPN or security services stopped. Managed installations may require the product’s administrator to disconnect management or change configuration.

Some processes are protected by macOS or their service policy even when the user authorizes an administrator operation. Killer reports that refusal; it does not change SIP, management settings, system extensions, launchd jobs, or endpoint-protection policies. A service supervisor may restart an app immediately after it exits, which is reported as a restart rather than a successful permanent shutdown.

The privileged executable is local to the app bundle and should be signed as part of a distributed app. Local ad-hoc builds are suitable for development on the same Mac. Production distribution additionally requires the developer’s signing identity and notarization. The force-quit app is unsandboxed because AppKit does not allow sandboxed apps to force-terminate other apps.

## One-time helper protocol

`KillerPrivileged` accepts exactly five positional arguments, in this order:

1. Process ID: an ASCII decimal integer greater than 1, within `Int32`.
2. Process start seconds: a positive ASCII decimal `UInt64`.
3. Process start microseconds: an ASCII decimal `UInt64` less than 1,000,000.
4. Expected owner UID: an ASCII decimal `UInt32`.
5. Expected absolute executable path: a nonempty path other than `/`.

The caller passes each argument separately with proper shell quoting when invoking it through the macOS administrator prompt. The helper requires effective UID 0 and independently reads the live process. It requires exact equality of PID/start time, owner UID, and executable path, then applies the shared protected-process policy and the shared force-kill operation. It accepts no shell expressions, process name patterns, launchd labels, or arbitrary commands.

The helper emits one UTF-8 JSON line to standard output with this schema:

```json
{"version":1,"status":"sent","message":"The force-quit signal was sent. Verify that the process exits."}
```

The stable `status` values are `sent`, `alreadyExited`, `identityChanged`, `permissionDenied`, `protectedProcess`, `failed`, `invalidArguments`, and `authorizationRequired`. `message` is explanatory text and is not a stable parsing key. Regular process outcomes, including refusals, exit with code 0 so the caller receives the structured result. Invalid arguments exit with code 64; an invocation without administrator privileges exits with code 77. Both still emit their JSON result. The caller separately handles cancellation or failure of the macOS authorization prompt. A `sent` status must be followed by independent exit verification in the app.

## Verification criteria

- A deliberately launched fixture that refuses ordinary termination exits when explicitly force quit.
- Search and discovery include background/accessory apps, and app launches/exits update the list.
- A stale selection, mismatched executable, or changed owner cannot become an unintended kill target.
- Protected processes, permission errors, process exits, and automatic restarts yield distinct results.
- The helper rejects missing, extra, malformed, negative, or out-of-range numeric arguments before taking action.
- Verification targets are intentionally created fixtures; unrelated user apps are not terminated for testing.

## Primary references

- [Apple: NSRunningApplication.forceTerminate](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate/) — sandbox limitation and the need to observe actual termination.
- [Apple: Quit a process in Activity Monitor](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1002/10.14/mac/15.0) — force-quit behavior, unsaved-work implications, and administrator authentication.
- [Apple: Creating launch daemons and agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) — launchd’s `KeepAlive` restart behavior.
- [Fortinet: FortiClient macOS processes](https://docs.fortinet.com/document/forticlient/7.4.7/administration-guide/234949/forticlient-macos-processes) — separate GUI, agent, VPN, and security services.
- [Fortinet: Disconnecting FortiClient Telemetry](https://docs.fortinet.com/document/forticlientmac/7.2.14/administration-guide/650724/disconnecting-forticlient-telemetry) — EMS management requirements for disabling/uninstalling managed clients.
