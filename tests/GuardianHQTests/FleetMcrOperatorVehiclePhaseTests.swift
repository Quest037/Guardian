import XCTest

@testable import GuardianHQ

final class FleetMcrOperatorVehiclePhaseTests: XCTestCase {

    func test_missionControlAssignmentTriageBadgeTitle_humanized_cases() {
        XCTAssertEqual(FleetMcrOperatorVehiclePhase.unknown.missionControlAssignmentTriageBadgeTitle, "Standby")
        XCTAssertEqual(FleetMcrOperatorVehiclePhase.onMission.missionControlAssignmentTriageBadgeTitle, "On mission")
        XCTAssertEqual(
            FleetMcrOperatorVehiclePhase.operatorParkAwaitingContinue.missionControlAssignmentTriageBadgeTitle,
            "Parked — continue available"
        )
    }
}
