import XCTest

@testable import GuardianCore

/// Regression guard for Phase 5 leave-tab persistence shape (wind-down is UI-orchestrated in ``TrainingLabController/leaveLab``).
final class TrainingLabLeaveTabContractTests: XCTestCase {
    func test_roster_snapshot_round_trip_preserves_learning_squad_and_zone_anchors() throws {
        let learningID = UUID()
        let squad = TrainingLabSquad(
            id: learningID,
            primary: TrainingLabRosterEntry(
                restoredLinkVehicleID: "sysid:1",
                vehicleClass: .ugvWheeled
            ),
            wingmen: [],
            formationPolicy: .default,
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 1, centerYM: 2, headingDeg: 3),
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 4, centerYM: 5, headingDeg: 6)
        )
        let snapshot = TrainingLabRosterStore.snapshot(from: [squad], learningSquadID: learningID)
        let restored = TrainingLabRosterStore.squads(from: snapshot)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(snapshot.learningSquadID, learningID)
        XCTAssertEqual(restored[0].startZoneAnchor?.centerXM, 1)
        XCTAssertEqual(restored[0].endZoneAnchor?.headingDeg, 6)
    }
}
