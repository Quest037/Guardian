import XCTest
@testable import GuardianHQ

final class MissionRunSquadConvoyAssemblyUtilitiesTests: XCTestCase {

    func test_isConvoyAssembled_trueWhenAllWingmenOnSlot() {
        let id = UUID()
        let slot = RouteCoordinate(lat: 50.75347, lon: -1.6190)
        let assembled = MissionRunSquadConvoyAssemblyUtilities.isConvoyAssembled(
            targets: [(assignmentID: id, slot: slot)],
            wingmanPositionByAssignmentID: [id: (lat: 50.753469, lon: -1.6190)],
            arrivalM: 1.5
        )
        XCTAssertTrue(assembled)
    }

    func test_isConvoyAssembled_falseWhenWingmanTooFar() {
        let id = UUID()
        let slot = RouteCoordinate(lat: 50.75347, lon: -1.6190)
        let assembled = MissionRunSquadConvoyAssemblyUtilities.isConvoyAssembled(
            targets: [(assignmentID: id, slot: slot)],
            wingmanPositionByAssignmentID: [id: (lat: 50.7530, lon: -1.6190)],
            arrivalM: 1.5
        )
        XCTAssertFalse(assembled)
    }

    func test_isConvoyAssembled_trueWhenNoWingmen() {
        XCTAssertTrue(
            MissionRunSquadConvoyAssemblyUtilities.isConvoyAssembled(
                targets: [],
                wingmanPositionByAssignmentID: [:]
            )
        )
    }
}
