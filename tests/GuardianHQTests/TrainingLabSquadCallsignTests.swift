import XCTest
@testable import GuardianHQ

final class TrainingLabSquadCallsignTests: XCTestCase {
    func test_primary_labels_follow_nato_alphabet() {
        XCTAssertEqual(TrainingLabSquadCallsign.primaryLabel(squadIndex: 0), "Alpha")
        XCTAssertEqual(TrainingLabSquadCallsign.primaryLabel(squadIndex: 1), "Beta")
        XCTAssertEqual(TrainingLabSquadCallsign.wingmanLabel(squadIndex: 0, wingmanIndex: 1), "Alpha:1")
        XCTAssertEqual(TrainingLabSquadCallsign.wingmanLabel(squadIndex: 2, wingmanIndex: 2), "Gamma:2")
    }

    func test_drag_payload_round_trip() {
        let entryID = UUID()
        let squadID = UUID()
        let payload = TrainingLabVehicleDragPayload.primary(entryID: entryID, squadID: squadID)
        let parsed = TrainingLabVehicleDragPayload.parse(payload.token)
        guard case .primary(let e, let s) = parsed else {
            return XCTFail("Expected primary payload")
        }
        XCTAssertEqual(e, entryID)
        XCTAssertEqual(s, squadID)
    }
}
