import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunOperatorDisplaySettingsTests: XCTestCase {
    func test_liveMapWhenTaskSelectedPick_reflectsIsolation() {
        XCTAssertEqual(
            MissionRunLiveMapWhenTaskSelectedPick.pick(isolates: true),
            .isolateMap
        )
        XCTAssertEqual(
            MissionRunLiveMapWhenTaskSelectedPick.pick(isolates: false),
            .fullMissionMap
        )
        XCTAssertTrue(MissionRunLiveMapWhenTaskSelectedPick.isolateMap.isolates)
        XCTAssertFalse(MissionRunLiveMapWhenTaskSelectedPick.fullMissionMap.isolates)
    }

    func test_operatorDisplaySettings_roundTripsJSONCodable() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        let samples: [MissionRunOperatorDisplaySettings] = [
            .default,
            MissionRunOperatorDisplaySettings(
                isolateLiveMapToSelectedTask: true,
                showMissionGeofencesOnMap: true,
                resetSimToStartPoseOnSuccessfulComplete: false,
                simBatteryDrainRateDuringRun: .fast
            ),
            MissionRunOperatorDisplaySettings(
                isolateLiveMapToSelectedTask: false,
                showMissionGeofencesOnMap: false,
                resetSimToStartPoseOnSuccessfulComplete: true,
                simBatteryDrainRateDuringRun: .none
            ),
        ]
        for original in samples {
            let data = try enc.encode(original)
            let decoded = try dec.decode(MissionRunOperatorDisplaySettings.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }

    func test_decode_legacy_liveMapIsolateOnTaskSelect_nilMapsToIsolateTrue() throws {
        let json = #"{"liveMapIsolateOnTaskSelect":null}"#
        let decoded = try JSONDecoder().decode(MissionRunOperatorDisplaySettings.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.isolateLiveMapToSelectedTask)
        XCTAssertTrue(decoded.showMissionGeofencesOnMap)
        XCTAssertFalse(decoded.resetSimToStartPoseOnSuccessfulComplete)
        XCTAssertEqual(decoded.simBatteryDrainRateDuringRun, .normal)
    }

    func test_decode_legacy_liveMapIsolateOnTaskSelect_explicitBool() throws {
        let json = #"{"liveMapIsolateOnTaskSelect":false}"#
        let decoded = try JSONDecoder().decode(MissionRunOperatorDisplaySettings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.isolateLiveMapToSelectedTask)
        XCTAssertTrue(decoded.showMissionGeofencesOnMap)
    }

    func test_decode_withoutShowGeofencesKey_defaultsShowTrue() throws {
        let json = #"{"isolateLiveMapToSelectedTask":true,"resetSimToStartPoseOnSuccessfulComplete":false,"simBatteryDrainRateDuringRun":"normal"}"#
        let decoded = try JSONDecoder().decode(MissionRunOperatorDisplaySettings.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.showMissionGeofencesOnMap)
    }

    func test_cloneFromAppDefaults_copiesGeneralSettingsMissionRunFields() {
        let app = GeneralSettingsStore()
        app.missionControlLiveMapHideOtherTasksOnTaskSelect = false
        app.missionControlShowMissionGeofencesOnMap = false
        app.missionRunResetSitlToStartPoseOnSuccessfulComplete = true
        let run = MissionRunOperatorDisplaySettings(
            isolateLiveMapToSelectedTask: app.missionControlLiveMapHideOtherTasksOnTaskSelect,
            showMissionGeofencesOnMap: app.missionControlShowMissionGeofencesOnMap,
            resetSimToStartPoseOnSuccessfulComplete: app.missionRunResetSitlToStartPoseOnSuccessfulComplete,
            simBatteryDrainRateDuringRun: app.missionRunSimBatteryDrainRate
        )
        XCTAssertFalse(run.isolateLiveMapToSelectedTask)
        XCTAssertFalse(run.showMissionGeofencesOnMap)
        XCTAssertTrue(run.resetSimToStartPoseOnSuccessfulComplete)
        XCTAssertEqual(run.simBatteryDrainRateDuringRun, app.missionRunSimBatteryDrainRate)
    }
}
