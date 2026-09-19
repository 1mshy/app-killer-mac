import Foundation
import KillerCore
import Testing
import Darwin

@Suite("Exact process control")
struct ProcessControllerTests {
    let controller = ProcessController()

    @Test("Process snapshot contains the running test process with a stable identity")
    func snapshotContainsSelf() throws {
        let current = try #require(controller.process(pid: getpid()))
        #expect(current.id.pid == getpid())
        #expect(current.id.startSeconds > 0)
        #expect(!current.executablePath.isEmpty)
        #expect(controller.snapshot().contains { $0.id == current.id })
        #expect(controller.protectionReason(for: current) != nil)
        #expect(!controller.hasExited(current.id))
    }

    @Test("System paths use directory boundaries and allow normal Apple apps")
    func protectionPolicy() {
        for path in ["/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
                     "/usr/libexec/securityd", "/usr/sbin/notifyd", "/usr/bin/yes", "/bin/sh", "/sbin/launchd"] {
            #expect(controller.protectionReason(for: record(pid: Int32.max, path: path)) != nil)
        }
        for path in ["/Applications/FortiClient.app/Contents/MacOS/FortiClient",
                     "/Library/Application Support/Fortinet/FortiClient/bin/fmon",
                     "/System/Applications/Calculator.app/Contents/MacOS/Calculator",
                     "/usr/libexec-custom/tool"] {
            #expect(controller.protectionReason(for: record(pid: Int32.max, path: path)) == nil)
        }
        #expect(controller.protectionReason(for: record(pid: 1, path: "/tmp/fake")) != nil)
        #expect(controller.protectionReason(for: record(pid: 0, path: "/tmp/fake")) != nil)
        #expect(controller.protectionReason(for: record(pid: -1, path: "/tmp/fake")) != nil)
        #expect(controller.protectionReason(for: record(pid: getppid(), path: "/tmp/fake")) != nil)
        #expect(controller.protectionReason(for: record(pid: Int32.max, path: "")) != nil)
    }

    @Test("An absent process reports that it has already exited")
    func absentProcess() {
        let absent = record(pid: Int32.max, path: "/tmp/killer-missing-fixture")
        #expect(controller.forceKill(absent) == .alreadyExited)
        #expect(controller.hasExited(absent.id))
    }

    @Test("Protected targets are refused without sending a signal")
    func refusesSelf() throws {
        let current = try #require(controller.process(pid: getpid()))
        guard case .protectedProcess = controller.forceKill(current) else {
            Issue.record("Killer must never signal its own process")
            return
        }
    }

    @Test("SIGKILL stops an owned disposable process that ignores SIGTERM")
    func stopsStubbornProcessAndRejectsStaleTargets() throws {
        let fixture = try DisposableProcess(controller: controller)
        defer { fixture.cleanUp() }
        let original = fixture.record
        #expect(controller.protectionReason(for: original) == nil)

        let stale = ProcessRecord(id: ProcessIdentity(pid: original.id.pid,
                                                      startSeconds: original.id.startSeconds + 1,
                                                      startMicroseconds: original.id.startMicroseconds),
                                  name: original.name, executablePath: original.executablePath,
                                  ownerUID: original.ownerUID, parentPID: original.parentPID)
        #expect(controller.forceKill(stale) == .identityChanged)
        let wrongPath = ProcessRecord(id: original.id, name: original.name,
                                      executablePath: original.executablePath + ".different",
                                      ownerUID: original.ownerUID, parentPID: original.parentPID)
        #expect(controller.forceKill(wrongPath) == .identityChanged)
        let wrongOwner = ProcessRecord(id: original.id, name: original.name,
                                       executablePath: original.executablePath,
                                       ownerUID: original.ownerUID + 1, parentPID: original.parentPID)
        #expect(controller.forceKill(wrongOwner) == .identityChanged)
        #expect(kill(original.id.pid, SIGTERM) == 0)
        Thread.sleep(forTimeInterval: 0.12)
        #expect(controller.process(pid: original.id.pid)?.id == original.id)
        #expect(controller.forceKill(original) == .sent)
        fixture.process.waitUntilExit()
        #expect(fixture.process.terminationReason == .uncaughtSignal)
        #expect(fixture.process.terminationStatus == SIGKILL)
        #expect(controller.process(pid: original.id.pid) == nil)
        #expect(controller.forceKill(original) == .alreadyExited)
    }

    @Test("An unreaped zombie is correctly recognized as exited")
    func detectsUnreapedChild() throws {
        let fixture = try DisposableProcess(controller: controller)
        defer { fixture.cleanUp() }
        let path = fixture.record.executablePath
        let argument = try #require(strdup(path))
        defer { free(argument) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [argument, nil]
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        var childPID: Int32 = 0
        let result = arguments.withUnsafeMutableBufferPointer { arguments in
            environment.withUnsafeMutableBufferPointer { environment in
                posix_spawn(&childPID, path, nil, nil, arguments.baseAddress!, environment.baseAddress!)
            }
        }
        try #require(result == 0)
        defer {
            kill(childPID, SIGKILL)
            waitpid(childPID, nil, 0)
        }
        var child: ProcessRecord?
        for _ in 0..<100 {
            child = controller.process(pid: childPID)
            if child != nil { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let target = try #require(child)
        #expect(!controller.hasExited(target.id))
        try #require(controller.forceKill(target) == .sent)
        for _ in 0..<100 {
            if controller.hasExited(target.id) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // No waitpid has happened: kill(pid, 0) still succeeds for this zombie.
        #expect(kill(childPID, 0) == 0)
        #expect(controller.process(pid: childPID) == nil)
        #expect(controller.hasExited(target.id))
    }

    private func record(pid: Int32, path: String) -> ProcessRecord {
        ProcessRecord(id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
                      name: "Fixture", executablePath: path, ownerUID: getuid(), parentPID: 1)
    }
}

private final class DisposableProcess {
    let process: Process
    let directory: URL
    let record: ProcessRecord

    init(controller: ProcessController) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("killer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("disposable-process")
        let source = """
        #include <signal.h>
        #include <stdio.h>
        #include <unistd.h>
        int main(void) {
            signal(SIGTERM, SIG_IGN);
            puts("ready");
            fflush(stdout);
            for (;;) pause();
        }
        """
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-x", "c", "-o", executable.path, "-"]
        let input = Pipe()
        compiler.standardInput = input
        try compiler.run()
        try input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
        try input.fileHandleForWriting.close()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw FixtureError.failedToCompile
        }
        let process = Process()
        process.executableURL = executable
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        // The handshake proves SIGTERM is ignored before the test signals the child.
        let ready = output.fileHandleForReading.readData(ofLength: 6)
        let expectedPath = executable.resolvingSymlinksInPath().path
        var found: ProcessRecord?
        for _ in 0..<200 {
            if let candidate = controller.process(pid: process.processIdentifier),
               URL(fileURLWithPath: candidate.executablePath).resolvingSymlinksInPath().path == expectedPath,
               ready == Data("ready\n".utf8) {
                found = candidate
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let found else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: directory)
            throw FixtureError.failedToStart
        }
        self.directory = directory
        self.process = process
        self.record = found
    }

    func cleanUp() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: directory)
    }

    enum FixtureError: Error { case failedToStart, failedToCompile }
}
