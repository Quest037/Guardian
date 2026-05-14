import XCTest
@testable import GuardianHQ

final class MissionTaskAttemptStateDisplayCopyTests: XCTestCase {

    func test_displayTitle_non_empty_for_all_cases() {
        for s in MissionTaskAttemptState.allCases {
            XCTAssertFalse(s.displayTitle.isEmpty, "displayTitle for \(s)")
        }
    }

    func test_displayTitle_distinct_from_mission_task_aborting_label() {
        let abortingSettled = MissionTaskState.aborting.displayTitle
        XCTAssertEqual(abortingSettled, "Aborting")
        XCTAssertNotEqual(MissionTaskAttemptState.abortMissionEnd.displayTitle, abortingSettled)
        XCTAssertNotEqual(MissionTaskAttemptState.recoveryMissionEnd.displayTitle, MissionTaskState.recovery.displayTitle)
    }

    func test_codable_round_trips_current_raw_values() throws {
        for s in MissionTaskAttemptState.allCases {
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(MissionTaskAttemptState.self, from: data)
            XCTAssertEqual(decoded, s)
        }
    }

    func test_codable_decodes_legacy_abort_raw_values() throws {
        for raw in ["abortWindDownIssued", "abortWindDownScheduledAfterCycle"] {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(MissionTaskAttemptState.self, from: data)
            XCTAssertEqual(decoded, .abortMissionEnd)
        }
    }

    func test_codable_decodes_legacy_recovery_raw_values() throws {
        for raw in ["recoveryWindDownIssued", "recoveryWindDownScheduledAfterCycle"] {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(MissionTaskAttemptState.self, from: data)
            XCTAssertEqual(decoded, .recoveryMissionEnd)
        }
    }
}
