import XCTest
@testable import GuardianCore

@MainActor
final class FleetNav2WarmStartTests: XCTestCase {
    func test_beginFleetNav2WarmStartAtApplicationLaunch_sets_starting_status() {
        let fleet = FleetLinkService()
        fleet.beginFleetNav2WarmStartAtApplicationLaunch()
        XCTAssertEqual(fleet.nav2TrainingStackStatus, "starting")
        XCTAssertFalse(fleet.nav2TrainingStackReady)
    }

    func test_nav2StackStatusPhrase_restarting() {
        XCTAssertEqual(
            TrainingPanelController.nav2StackStatusPhrase("restarting"),
            "Nav2 restarting"
        )
    }
}
