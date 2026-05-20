import XCTest
@testable import GuardianCore

@MainActor
final class MissionControlLiveTasksWindDownNoticeTests: XCTestCase {
    func test_flags_setupStatus_returnsFalse() {
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let run = MissionRunEnvironment(mission: mission)
        run.status = .setup
        run.gracefulStopKind = .abortAfterCycle
        let flags = MissionControlLiveTasksWindDownNotice.flags(for: run)
        XCTAssertFalse(flags.abort)
        XCTAssertFalse(flags.complete)
    }

    func test_flags_runningWithGracefulAbort_showsAbort() {
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let run = MissionRunEnvironment(mission: mission)
        run.status = .running
        run.gracefulStopKind = .abortAfterCycle
        let flags = MissionControlLiveTasksWindDownNotice.flags(for: run)
        XCTAssertTrue(flags.abort)
        XCTAssertFalse(flags.complete)
    }
}
