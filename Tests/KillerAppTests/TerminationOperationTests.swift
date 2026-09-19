import AppKit
import Darwin
import Foundation
import KillerCore
import Testing
@testable import Killer

@Suite("App termination workflow")
struct TerminationOperationTests {
    private let controller = ProcessController()

    @Test("Force quit verifies an owned stubborn fixture exited")
    func stopsOwnedFixture() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let child = try fixture.launch()
        defer { child.cleanUp() }
        #expect(Darwin.kill(child.record.id.pid, SIGTERM) == 0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.process(pid: child.record.id.pid)?.id == child.record.id)

        let result = await stop(child.record)

        child.process.waitUntilExit()
        #expect(result.outcome == .stopped)
        #expect(result.pid == child.record.id.pid)
        #expect(child.process.terminationReason == .uncaughtSignal)
        #expect(child.process.terminationStatus == SIGKILL)
    }

    @Test("An existing sibling is not falsely reported as a restart")
    func excludesExistingSiblingFromRestartDetection() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let selected = try fixture.launch()
        defer { selected.cleanUp() }
        let sibling = try fixture.launch()
        defer { sibling.cleanUp() }

        let result = await stop(selected.record)

        #expect(result.outcome == .stopped)
        #expect(controller.process(pid: sibling.record.id.pid)?.id == sibling.record.id)
    }

    @Test("A replacement after the selected process exits is reported and left running")
    func detectsRestartWithoutRepeatedKilling() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let selected = try fixture.launch()
        defer { selected.cleanUp() }
        let operation = Task { await stop(selected.record) }

        // Wait until the actual selected fixture is gone. This creates a new
        // process only after the operation has captured its baseline and acted.
        for _ in 0..<200 {
            if controller.process(pid: selected.record.id.pid)?.id != selected.record.id { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.process(pid: selected.record.id.pid)?.id != selected.record.id)
        let replacement = try fixture.launch()
        defer { replacement.cleanUp() }
        let result = await operation.value

        #expect(result.outcome == .restarted)
        #expect(result.detail.contains(String(replacement.record.id.pid)))
        #expect(controller.process(pid: replacement.record.id.pid)?.id == replacement.record.id)
    }

    @Test("An already exited owned fixture is reported without affecting its replacement")
    func alreadyGone() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let original = try fixture.launch()
        defer { original.cleanUp() }
        original.cleanUp()
        let replacement = try fixture.launch()
        defer { replacement.cleanUp() }

        let result = await stop(original.record)

        #expect(result.outcome == .alreadyStopped)
        #expect(controller.process(pid: replacement.record.id.pid)?.id == replacement.record.id)
    }

    @Test("A stale birth identity is refused and the selected fixture stays alive")
    func refusesStaleIdentity() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let child = try fixture.launch()
        defer { child.cleanUp() }
        let stale = ProcessRecord(
            id: ProcessIdentity(pid: child.record.id.pid,
                                startSeconds: child.record.id.startSeconds + 1,
                                startMicroseconds: child.record.id.startMicroseconds),
            name: child.record.name, executablePath: child.record.executablePath,
            ownerUID: child.record.ownerUID, parentPID: child.record.parentPID)

        let result = await stop(stale)

        #expect(result.outcome == .changed)
        #expect(controller.process(pid: child.record.id.pid)?.id == child.record.id)
    }

    @Test("A protected self target is reported without attempting authorization")
    func protectedTarget() async throws {
        let record = try #require(controller.process(pid: getpid()))

        let result = await stop(record)

        #expect(result.outcome == .protected)
        #expect(controller.process(pid: getpid())?.id == record.id)
    }

    @Test("A missing administrator helper fails before showing authorization")
    func missingHelper() throws {
        let record = try #require(controller.process(pid: getpid()))
        let result = TerminationOperation.authorize(record: record,
                                                    helperPath: "/nonexistent/killer-test-\(UUID().uuidString)")
        guard case .failure(let failure) = result else {
            Issue.record("A missing helper must fail before authorization")
            return
        }
        #expect(!failure.cancelled)
        #expect(failure.message.contains("missing"))
    }

    @Test("Shell and AppleScript quoting preserve literal values without evaluating them",
          arguments: ["", "plain", "space separated", "single'quote", "double\"quote", "back\\slash",
                      "$(printf INJECTION); printf INJECTION", "`printf INJECTION`", "line\nbreak\rand\ttab", "🛑 Café"])
    func quotingRoundTrip(_ value: String) throws {
        let quoted = TerminationOperation.shellQuote(value)
        let direct = try execute("/bin/sh", ["-c", "printf '%s' \(quoted)"])
        #expect(direct.status == 0)
        // Foundation may canonically decompose Unicode when marshaling process
        // arguments. Swift string equality accepts that equivalent spelling.
        #expect(String(decoding: direct.data, as: UTF8.self) == value)

        // Return hex to keep osascript's output formatting from modifying
        // embedded/trailing line breaks in the value under test.
        let command = "printf '%s' \(quoted) | /usr/bin/od -An -tx1 | /usr/bin/tr -d ' \\n'"
        let script = "do shell script \"\(TerminationOperation.appleScriptEscape(command))\""
        let appleScript = try execute("/usr/bin/osascript", ["-e", script])
        #expect(appleScript.status == 0, "\(appleScript.error)")
        let actualHex = String(decoding: appleScript.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let hexCharacters = Array(actualHex)
        #expect(hexCharacters.count.isMultiple(of: 2))
        let actualBytes = stride(from: 0, to: hexCharacters.count - (hexCharacters.count % 2), by: 2).compactMap {
            UInt8(String(hexCharacters[$0...($0 + 1)]), radix: 16)
        }
        #expect(actualBytes.count * 2 == hexCharacters.count)
        #expect(String(decoding: actualBytes, as: UTF8.self) == value)
    }

    private func stop(_ record: ProcessRecord) async -> ActivityEntry {
        await TerminationOperation.run(record: record, name: "Disposable test fixture",
                                       administrator: false, helperPath: "/unused")
    }
}

@Suite("App selection and safety state")
@MainActor
struct AppModelTests {
    @Test("Protected rows cannot open a force-quit confirmation")
    func protectedSelection() throws {
        let record = try #require(ProcessController().process(pid: getpid()))
        let app = AppProcess(record: record, displayName: "Protected fixture", bundleIdentifier: nil,
                             bundleURL: nil, icon: nil, isApplication: false,
                             protection: "Protected for this test")
        let model = AppModel()
        model.requestTermination(app)
        #expect(!model.showConfirmation)
        #expect(model.pendingTarget == nil)
        #expect(model.activeOperation == nil)
    }

    @Test("Refresh removes stale selection and search finds an owned background fixture")
    func refreshAndSearch() async throws {
        let fixture = try FixtureDirectory()
        defer { fixture.remove() }
        let child = try fixture.launch()
        defer { child.cleanUp() }
        let model = AppModel()
        model.scope = .background
        model.query = String(child.record.id.pid)
        await model.refresh()
        #expect(model.visibleProcesses.contains { $0.id == child.record.id })
        model.selection = child.record.id
        child.cleanUp()

        await model.refresh()

        #expect(model.selection == nil)
        #expect(!model.processes.contains { $0.id == child.record.id })
        #expect(!model.isRefreshing)
    }
}

private final class FixtureDirectory: @unchecked Sendable {
    let directory: URL
    let executable: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("killer-app-tests-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("owned-stubborn-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Copied Apple system binaries can be killed by macOS code-signing
        // policy. Build a fixture we own, with an explicit readiness handshake.
        let source = directory.appendingPathComponent("fixture.c")
        try """
        #include <signal.h>
        #include <unistd.h>
        int main(void) {
            signal(SIGTERM, SIG_IGN);
            if (write(STDOUT_FILENO, "R", 1) != 1) return 1;
            for (;;) pause();
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let compilation = try execute("/usr/bin/xcrun", ["clang", source.path, "-o", executable.path])
        guard compilation.status == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw FixtureError.failedToCompile(compilation.error)
        }
    }

    func launch() throws -> OwnedChild {
        let process = Process()
        process.executableURL = executable
        let readiness = Pipe()
        process.standardOutput = readiness
        try process.run()
        let ready = readiness.fileHandleForReading.readData(ofLength: 1)
        let expectedPath = executable.resolvingSymlinksInPath().path
        for _ in 0..<200 {
            if ready == Data("R".utf8), let record = ProcessController().process(pid: process.processIdentifier),
               URL(fileURLWithPath: record.executablePath).resolvingSymlinksInPath().path == expectedPath {
                return OwnedChild(process: process, record: record)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        throw FixtureError.failedToStart
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
    enum FixtureError: Error {
        case failedToStart
        case failedToCompile(String)
    }
}

private final class OwnedChild: @unchecked Sendable {
    let process: Process
    let record: ProcessRecord

    init(process: Process, record: ProcessRecord) {
        self.process = process
        self.record = record
    }

    func cleanUp() {
        // Only this test's child is ever touched. A stale Process object is not
        // sufficient: verify the saved birth identity before cleanup signals.
        if process.isRunning, ProcessController().process(pid: record.id.pid)?.id == record.id {
            Darwin.kill(record.id.pid, SIGKILL)
        }
        process.waitUntilExit()
    }
}

private func execute(_ executable: String, _ arguments: [String]) throws -> (status: Int32, data: Data, error: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, data, String(decoding: error, as: UTF8.self))
}
