import Foundation
import XCTest

@testable import GuardianHQ

final class MissionControlReservePoolMapMarkerIDTests: XCTestCase {

    func test_encode_decode_task_roundtrip() {
        let task = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let slot = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let raw = MissionControlReservePoolMapMarkerID.encode(taskID: task, slotID: slot)
        XCTAssertEqual(MissionControlReservePoolMapMarkerID.decodeTaskID(raw), task)
        let decoded = MissionControlReservePoolMapMarkerID.decodeBerth(raw)
        XCTAssertEqual(decoded?.taskID, task)
        XCTAssertEqual(decoded?.slotID, slot)
    }

    func test_decode_returns_nil_for_roster_uuid_string() {
        let roster = UUID().uuidString
        XCTAssertNil(MissionControlReservePoolMapMarkerID.decodeTaskID(roster))
    }
}
