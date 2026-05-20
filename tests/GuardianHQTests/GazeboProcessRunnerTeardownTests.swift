import XCTest
@testable import GuardianCore

@MainActor
final class GazeboProcessRunnerTeardownTests: XCTestCase {
    func test_stopAndWait_terminatesSleepProcess() async throws {
        let runner = GazeboProcessRunner()
        let spec = try makeSleepSpec(seconds: 30)
        try runner.start(spec: spec)
        XCTAssertTrue(runner.isRunning)

        let stopped = await runner.stopAndWait(timeout: 4)
        XCTAssertTrue(stopped)
        XCTAssertFalse(runner.isRunning)
    }

    private func makeSleepSpec(seconds: Int) throws -> GazeboProcessSpec {
        let sleepPath = "/bin/sleep"
        guard FileManager.default.isExecutableFile(atPath: sleepPath) else {
            throw XCTSkip("sleep binary unavailable")
        }
        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-gazebo-runner-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        return GazeboProcessSpec(
            executable: sleepPath,
            arguments: ["\(seconds)"],
            currentDirectoryURL: logDir,
            environment: [:],
            worldPath: logDir.path,
            logDirectoryURL: logDir
        )
    }
}
