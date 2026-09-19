import CProcess
import Foundation

public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

public struct ProcessRecord: Identifiable, Hashable, Sendable {
    public let id: ProcessIdentity
    public let name: String
    public let executablePath: String
    public let ownerUID: UInt32
    public let parentPID: Int32

    public init(id: ProcessIdentity, name: String, executablePath: String, ownerUID: UInt32, parentPID: Int32) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.ownerUID = ownerUID
        self.parentPID = parentPID
    }
}

public enum SignalResult: Equatable, Sendable {
    case sent
    case alreadyExited
    case identityChanged
    case permissionDenied
    case protectedProcess(String)
    case failed(String)
}

/// Provides bounded process snapshots and exact, revalidated SIGKILL operations.
/// A sent signal is only an acknowledgement; callers must verify the process exits.
public struct ProcessController: Sendable {
    public init() {}

    public func snapshot() -> [ProcessRecord] {
        let estimatedCount = killer_list_processes(nil, 0)
        guard estimatedCount > 0 else { return [] }
        // Leave room for processes launched while the kernel fills the list.
        var capacity = max(256, Int(estimatedCount) + 256)
        for _ in 0..<3 {
            var processIDs = [Int32](repeating: 0, count: capacity)
            let count = processIDs.withUnsafeMutableBufferPointer {
                killer_list_processes($0.baseAddress, Int32($0.count))
            }
            guard count >= 0 else { return [] }
            if Int(count) >= capacity {
                capacity *= 2
                continue
            }
            return processIDs.prefix(Int(count)).compactMap { process(pid: $0) }
                .sorted { $0.id.pid < $1.id.pid }
        }
        return []
    }

    public func process(pid: Int32) -> ProcessRecord? {
        var info = killer_process_info()
        guard killer_read_process(pid, &info) == 0 else { return nil }
        let name = withUnsafeBytes(of: info.name) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let path = withUnsafeBytes(of: info.executable_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessRecord(
            id: ProcessIdentity(pid: info.pid, startSeconds: info.start_seconds,
                                startMicroseconds: info.start_microseconds),
            name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name,
            executablePath: path,
            ownerUID: info.owner_uid,
            parentPID: info.parent_pid
        )
    }

    public func forceKill(_ target: ProcessRecord) -> SignalResult {
        var errorNumber: Int32 = 0
        let result = target.executablePath.withCString { path in
            killer_force_kill(target.id.pid, target.id.startSeconds,
                              target.id.startMicroseconds, target.ownerUID, path, &errorNumber)
        }
        switch result {
        case Int32(KILLER_SIGNAL_SENT.rawValue): return .sent
        case Int32(KILLER_SIGNAL_EXITED.rawValue): return .alreadyExited
        case Int32(KILLER_SIGNAL_IDENTITY_CHANGED.rawValue): return .identityChanged
        case Int32(KILLER_SIGNAL_PERMISSION_DENIED.rawValue): return .permissionDenied
        case Int32(KILLER_SIGNAL_PROTECTED.rawValue):
            return .protectedProcess(protectionReason(for: target) ?? "This process is protected by macOS.")
        default:
            return .failed(errorNumber == 0 ? "The process could not be stopped." : String(cString: strerror(errorNumber)))
        }
    }

    /// Confirms that the original process has exited, including an unreaped zombie.
    /// Returns false when the process cannot be inspected and its absence is unproven.
    public func hasExited(_ identity: ProcessIdentity) -> Bool {
        killer_has_exited(identity.pid, identity.startSeconds, identity.startMicroseconds) != 0
    }

    public func protectionReason(for target: ProcessRecord) -> String? {
        target.executablePath.withCString { path in
            guard let reason = killer_protection_reason(target.id.pid, path) else { return nil }
            return String(cString: reason)
        }
    }
}
