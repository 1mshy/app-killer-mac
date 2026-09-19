import Darwin
import Foundation
import KillerCore

// The caller receives one JSON line, including for refusals. `sent` means only
// that the signal was accepted; the app must independently verify termination.
private struct HelperResponse: Encodable {
    let version = 1
    let status: String
    let message: String
}

private struct TargetArguments {
    let identity: ProcessIdentity
    let ownerUID: UInt32
    let executablePath: String

    init?(_ arguments: [String]) {
        guard arguments.count == 5,
              arguments.prefix(4).allSatisfy(Self.isUnsignedDecimal),
              let pid = Int32(arguments[0]), pid > 1,
              let seconds = UInt64(arguments[1]), seconds > 0,
              let microseconds = UInt64(arguments[2]), microseconds < 1_000_000,
              let owner = UInt32(arguments[3]),
              arguments[4].hasPrefix("/"), arguments[4] != "/",
              !arguments[4].utf8.contains(0)
        else { return nil }

        identity = ProcessIdentity(pid: pid, startSeconds: seconds, startMicroseconds: microseconds)
        ownerUID = owner
        executablePath = arguments[4]
    }

    private static func isUnsignedDecimal(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

private func finish(_ status: String, _ message: String, exitCode: Int32 = 0) -> Never {
    let response = HelperResponse(status: status, message: message)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // All response fields are ordinary strings. Keep a protocol-shaped fallback
    // in the unlikely event that encoding fails, rather than writing diagnostics.
    var data = (try? encoder.encode(response))
        ?? Data(#"{"version":1,"status":"failed","message":"Could not encode the result."}"#.utf8)
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
    exit(exitCode)
}

guard let arguments = TargetArguments(Array(CommandLine.arguments.dropFirst())) else {
    finish("invalidArguments", "Expected PID, start seconds, start microseconds, owner UID, and absolute executable path.", exitCode: 64)
}

guard geteuid() == 0 else {
    finish("authorizationRequired", "Run this one-time helper through Killer's administrator authorization.", exitCode: 77)
}

let controller = ProcessController()
guard let current = controller.process(pid: arguments.identity.pid) else {
    // An unreadable process is not proof of an exit. Signal 0 only checks
    // existence/permission and never terminates the target.
    if Darwin.kill(arguments.identity.pid, 0) == -1, errno == ESRCH {
        finish("alreadyExited", "The selected process is no longer running.")
    }
    finish("failed", "The selected process could not be inspected safely. Refresh the app list before trying again.")
}

guard current.id == arguments.identity,
      current.ownerUID == arguments.ownerUID,
      current.executablePath == arguments.executablePath else {
    finish("identityChanged", "The selected process changed. Refresh the app list before trying again.")
}

if let reason = controller.protectionReason(for: current) {
    finish("protectedProcess", reason)
}

switch controller.forceKill(current) {
case .sent:
    finish("sent", "The force-quit signal was sent. Verify that the process exits.")
case .alreadyExited:
    finish("alreadyExited", "The selected process is no longer running.")
case .identityChanged:
    finish("identityChanged", "The selected process changed. Refresh the app list before trying again.")
case .permissionDenied:
    finish("permissionDenied", "macOS denied termination even with administrator authorization.")
case .protectedProcess(let reason):
    finish("protectedProcess", reason)
case .failed(let reason):
    finish("failed", reason)
}
