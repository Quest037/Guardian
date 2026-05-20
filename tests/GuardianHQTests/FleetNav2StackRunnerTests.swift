import XCTest
@testable import GuardianCore

final class FleetNav2StackRunnerTests: XCTestCase {
    func test_stderrTail_afterProcessExits_returns_stderr_without_blocking_main() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", "echo guardian_nav2_stderr_test 1>&2"]
        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err
        try? proc.run()
        proc.waitUntilExit()

        let tail = FleetNav2StackRunner.stderrTail(
            afterTerminating: proc,
            handle: err.fileHandleForReading,
            maxBytes: 4096
        )
        XCTAssertTrue(tail.contains("guardian_nav2_stderr_test"))
    }

    func test_stderrTail_whenNoProcess_returns_empty() {
        let tail = FleetNav2StackRunner.stderrTail(
            afterTerminating: Process(),
            handle: FileHandle.nullDevice,
            maxBytes: 256
        )
        XCTAssertEqual(tail, "")
    }
}
