import AppKit
import Foundation
import KillerCore
import Observation

struct AppProcess: Identifiable {
    let record: ProcessRecord
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let icon: NSImage?
    let isApplication: Bool
    let protection: String?
    var id: ProcessIdentity { record.id }
    var needsAdministrator: Bool { record.ownerUID != getuid() }
    var owner: String {
        if record.ownerUID == getuid() { return "You" }
        if record.ownerUID == 0 { return "System administrator" }
        return "User \(record.ownerUID)"
    }
}

enum ProcessScope: String, CaseIterable, Identifiable {
    case applications = "Applications"
    case background = "Background processes"
    case activity = "Recent activity"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .applications: "app.stack"
        case .background: "gearshape.2"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

struct ActivityEntry: Identifiable, Sendable {
    enum Outcome: String, Sendable {
        case stopped = "Stopped"
        case alreadyStopped = "Already stopped"
        case restarted = "Restarted"
        case denied = "Permission denied"
        case protected = "Protected process"
        case changed = "Process changed"
        case stillRunning = "Still running"
        case cancelled = "Cancelled"
        case failed = "Couldn’t stop"
        var isSuccess: Bool { self == .stopped || self == .alreadyStopped }
        var symbol: String {
            if isSuccess { return "checkmark.circle.fill" }
            if self == .restarted { return "arrow.clockwise.circle.fill" }
            if self == .cancelled { return "minus.circle" }
            return "exclamationmark.circle.fill"
        }
    }
    let id = UUID()
    let date = Date()
    let name: String
    let pid: Int32
    let outcome: Outcome
    let detail: String
}

@MainActor @Observable
final class AppModel {
    var processes: [AppProcess] = []
    var scope: ProcessScope = .applications
    var query = ""
    var selection: ProcessIdentity?
    var activity: [ActivityEntry] = []
    var isRefreshing = false
    var activeOperation: ProcessIdentity?
    var pendingTarget: AppProcess?
    var showConfirmation = false
    var useAdministrator = false
    var latestResult: ActivityEntry?
    var lastRefresh: Date?

    var selectedProcess: AppProcess? { processes.first { $0.id == selection } }
    var applicationCount: Int { processes.filter(\.isApplication).count }
    var backgroundCount: Int { processes.filter { !$0.isApplication }.count }
    var visibleProcesses: [AppProcess] {
        processes.filter { process in
            let inScope = scope == .applications ? process.isApplication : !process.isApplication
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            let searchable = "\(process.displayName) \(process.record.name) \(process.record.executablePath) \(process.bundleIdentifier ?? "") \(process.id.pid)"
            return inScope && terms.allSatisfy { searchable.localizedStandardContains($0) }
        }
    }
    var visibleActivity: [ActivityEntry] {
        activity.filter { query.isEmpty || "\($0.name) \($0.pid) \($0.outcome.rawValue)".localizedStandardContains(query) }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let records = await Task.detached(priority: .utility) { ProcessController().snapshot() }.value
        let apps = Dictionary(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let controller = ProcessController()
        processes = records.compactMap { record in
            guard record.id.pid != getpid() else { return nil }
            let app = apps[record.id.pid]
            let isNestedHelper = app?.bundleURL?.path.contains(".app/Contents/") == true
            let isApp = app != nil && app?.activationPolicy != .prohibited && !isNestedHelper
            let protection = controller.protectionReason(for: record)
            // Keep the main list actionable; essential macOS services are omitted.
            guard protection == nil else { return nil }
            return AppProcess(record: record, displayName: app?.localizedName ?? record.name,
                              bundleIdentifier: app?.bundleIdentifier, bundleURL: app?.bundleURL,
                              icon: app?.icon, isApplication: isApp, protection: protection)
        }.sorted {
            let comparison = $0.displayName.localizedStandardCompare($1.displayName)
            return comparison == .orderedSame ? $0.id.pid < $1.id.pid : comparison == .orderedAscending
        }
        if let selection, !processes.contains(where: { $0.id == selection }) { self.selection = nil }
        lastRefresh = Date()
        isRefreshing = false
    }

    func requestTermination(_ process: AppProcess, administrator: Bool? = nil) {
        guard activeOperation == nil, process.protection == nil else { return }
        pendingTarget = process
        useAdministrator = administrator ?? process.needsAdministrator
        showConfirmation = true
    }

    func confirmTermination() {
        guard let target = pendingTarget, activeOperation == nil else { return }
        let admin = useAdministrator
        showConfirmation = false
        pendingTarget = nil
        activeOperation = target.id
        let record = target.record
        let name = target.displayName
        let helperPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/KillerPrivileged").path
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await TerminationOperation.run(record: record, name: name, administrator: admin, helperPath: helperPath)
            }.value
            activity.insert(result, at: 0)
            if activity.count > 50 { activity.removeLast(activity.count - 50) }
            latestResult = result
            activeOperation = nil
            await refresh()
        }
    }
}

enum TerminationOperation {
    static func run(record: ProcessRecord, name: String, administrator: Bool, helperPath: String) async -> ActivityEntry {
        let controller = ProcessController()
        let baseline = Set(controller.snapshot().filter { $0.executablePath == record.executablePath && $0.ownerUID == record.ownerUID }.map(\.id))
        let signal: SignalResult
        if administrator {
            switch authorize(record: record, helperPath: helperPath) {
            case .success(let result): signal = result
            case .failure(let error):
                return ActivityEntry(name: name, pid: record.id.pid, outcome: error.cancelled ? .cancelled : .failed, detail: error.message)
            }
        } else {
            signal = controller.forceKill(record)
        }
        func entry(_ outcome: ActivityEntry.Outcome, _ detail: String) -> ActivityEntry {
            ActivityEntry(name: name, pid: record.id.pid, outcome: outcome, detail: detail)
        }
        switch signal {
        case .alreadyExited: return entry(.alreadyStopped, "This process had already exited. Nothing else was stopped.")
        case .identityChanged: return entry(.changed, "The selected process changed since it was listed. Select the current process and try again.")
        case .permissionDenied:
            return entry(.denied, administrator
                         ? "macOS or the app’s management policy refused the request. For a managed app, use its supported shutdown or contact your administrator."
                         : "This process needs additional permission. Select it and choose Force Quit as Administrator.")
        case .protectedProcess(let reason): return entry(.protected, reason)
        case .failed(let message): return entry(.failed, message)
        case .sent: break
        }
        var exited = false
        for _ in 0..<20 {
            if controller.hasExited(record.id) { exited = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard exited else { return entry(.stillRunning, "The stop request was sent, but the process has not exited. It may be protected or waiting on the operating system.") }
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(250))
            let replacements = controller.snapshot().filter {
                $0.executablePath == record.executablePath && $0.ownerUID == record.ownerUID && !baseline.contains($0.id)
            }
            if let replacement = replacements.first {
                return entry(.restarted, "The original process stopped, but a new process using the same executable appeared (PID \(replacement.id.pid)). A background service may be reopening it. Killer won’t stop it repeatedly.")
            }
        }
        return entry(.stopped, "Process \(record.id.pid) exited. No replacement was detected during the two-second check. Separate helpers may still be running.")
    }

    struct AuthorizationFailure: Error {
        let message: String
        let cancelled: Bool
    }
    private struct HelperReply: Decodable { let version: Int; let status: String; let message: String }

    static func authorize(record: ProcessRecord, helperPath: String) -> Result<SignalResult, AuthorizationFailure> {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return .failure(.init(message: "The administrator helper is missing. Run the bundled Killer.app created by scripts/build.sh.", cancelled: false))
        }
        // Quote each argument for the shell, then quote the whole command for AppleScript.
        let arguments = [helperPath, String(record.id.pid), String(record.id.startSeconds),
                         String(record.id.startMicroseconds), String(record.ownerUID), record.executablePath]
        let command = arguments.map(shellQuote).joined(separator: " ")
        let script = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let message = String(decoding: errorData, as: UTF8.self)
                let cancelled = message.contains("(-128)")
                return .failure(.init(message: cancelled ? "Administrator authorization was cancelled. No stop request was sent." : "Administrator authorization failed. \(message.trimmingCharacters(in: .whitespacesAndNewlines))", cancelled: cancelled))
            }
            let reply = try JSONDecoder().decode(HelperReply.self, from: data)
            guard reply.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            switch reply.status {
            case "sent": return .success(.sent)
            case "alreadyExited": return .success(.alreadyExited)
            case "identityChanged": return .success(.identityChanged)
            case "permissionDenied": return .success(.permissionDenied)
            case "protectedProcess": return .success(.protectedProcess(reply.message))
            default: return .success(.failed(reply.message))
            }
        } catch {
            return .failure(.init(message: "Couldn’t run the administrator helper: \(error.localizedDescription)", cancelled: false))
        }
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
    }
}
