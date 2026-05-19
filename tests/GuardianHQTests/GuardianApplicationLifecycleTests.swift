import XCTest

@testable import GuardianHQ

@MainActor
final class GuardianApplicationLifecycleTests: XCTestCase {
    override func tearDown() {
        let lifecycle = GuardianApplicationLifecycle.shared
        while lifecycle.isBackgroundLabRunActive {
            lifecycle.endBackgroundLabRun()
        }
        lifecycle.applicationDidBecomeActive()
        super.tearDown()
    }

    func test_resignActive_pauses_nav2_when_no_lab_run() {
        let lifecycle = GuardianApplicationLifecycle.shared
        let fleet = FleetLinkService()
        lifecycle.noteFleetLinkService(fleet)
        fleet.beginFleetNav2WarmStartAtApplicationLaunch()
        lifecycle.applicationWillResignActive()
        XCTAssertFalse(lifecycle.isApplicationActive)
        XCTAssertEqual(fleet.nav2TrainingStackStatus, "inactive")
    }

    func test_lab_run_keeps_nav2_warm_while_inactive() {
        let lifecycle = GuardianApplicationLifecycle.shared
        let fleet = FleetLinkService()
        lifecycle.noteFleetLinkService(fleet)
        fleet.beginFleetNav2WarmStartAtApplicationLaunch()
        lifecycle.beginBackgroundLabRun()
        lifecycle.applicationWillResignActive()
        XCTAssertFalse(lifecycle.isApplicationActive)
        XCTAssertTrue(lifecycle.isBackgroundLabRunActive)
        lifecycle.endBackgroundLabRun()
        lifecycle.applicationDidBecomeActive()
        XCTAssertTrue(lifecycle.isApplicationActive)
    }
}
