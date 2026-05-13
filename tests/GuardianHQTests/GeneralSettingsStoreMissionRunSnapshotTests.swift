import XCTest

@testable import GuardianHQ

@MainActor
final class GeneralSettingsStoreMissionRunSnapshotTests: XCTestCase {
    func test_missionControlLiveMapHideOtherTasksOnTaskSelect_defaultsTrueAndPersists() {
        let suiteName = "test.generalSettings.missionRun.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let first = GeneralSettingsStore(userDefaults: ud)
        XCTAssertTrue(first.missionControlLiveMapHideOtherTasksOnTaskSelect)

        first.missionControlLiveMapHideOtherTasksOnTaskSelect = false
        let second = GeneralSettingsStore(userDefaults: ud)
        XCTAssertFalse(second.missionControlLiveMapHideOtherTasksOnTaskSelect)
    }

    func test_decodeSnapshotWithoutLiveMapIsolationKey_defaultsTrue() throws {
        let suiteName = "test.generalSettings.missionRun.decode.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot"}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertTrue(store.missionControlLiveMapHideOtherTasksOnTaskSelect)
    }

    func test_decodeSnapshotWithExplicitFalse_preservesFalse() throws {
        let suiteName = "test.generalSettings.missionRun.decode.false.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot","missionControlLiveMapHideOtherTasksOnTaskSelect":false}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertFalse(store.missionControlLiveMapHideOtherTasksOnTaskSelect)
    }

    func test_missionRunResetSitlToStartPoseOnSuccessfulComplete_defaultsFalseAndPersists() {
        let suiteName = "test.generalSettings.simReset.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let first = GeneralSettingsStore(userDefaults: ud)
        XCTAssertFalse(first.missionRunResetSitlToStartPoseOnSuccessfulComplete)

        first.missionRunResetSitlToStartPoseOnSuccessfulComplete = true
        let second = GeneralSettingsStore(userDefaults: ud)
        XCTAssertTrue(second.missionRunResetSitlToStartPoseOnSuccessfulComplete)
    }

    func test_decodeSnapshotWithoutSitlResetKey_defaultsFalse() throws {
        let suiteName = "test.generalSettings.simReset.decode.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot"}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertFalse(store.missionRunResetSitlToStartPoseOnSuccessfulComplete)
    }

    func test_missionRunSimBatteryDrainRate_defaultsNormalAndPersists() {
        let suiteName = "test.generalSettings.missionRun.drain.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let first = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(first.missionRunSimBatteryDrainRate, .normal)

        first.missionRunSimBatteryDrainRate = .none
        let second = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(second.missionRunSimBatteryDrainRate, .none)
    }

    func test_decodeSnapshotWithoutMissionRunSimBatteryDrainKey_defaultsNormal() throws {
        let suiteName = "test.generalSettings.missionRun.drain.decode.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot"}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(store.missionRunSimBatteryDrainRate, .normal)
    }

    func test_liveDriveSimBatteryDrainRate_defaultsNormalAndPersists() {
        let suiteName = "test.generalSettings.liveDrive.drain.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let first = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(first.liveDriveSimBatteryDrainRate, .normal)

        first.liveDriveSimBatteryDrainRate = .none
        let second = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(second.liveDriveSimBatteryDrainRate, .none)
    }

    func test_decodeLegacyDefaultSimBatteryDrainRate_migratesToLiveDriveSimBatteryDrainRate() throws {
        let suiteName = "test.generalSettings.liveDrive.legacyDrain.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot","defaultSimBatteryDrainRate":"fast"}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertEqual(store.liveDriveSimBatteryDrainRate, .fast)
    }

    func test_missionControlShowMissionGeofencesOnMap_defaultsTrueAndPersists() {
        let suiteName = "test.generalSettings.missionRun.geofenceShow.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let first = GeneralSettingsStore(userDefaults: ud)
        XCTAssertTrue(first.missionControlShowMissionGeofencesOnMap)

        first.missionControlShowMissionGeofencesOnMap = false
        let second = GeneralSettingsStore(userDefaults: ud)
        XCTAssertFalse(second.missionControlShowMissionGeofencesOnMap)
    }

    func test_decodeSnapshotWithoutMissionControlShowGeofencesKey_defaultsTrue() throws {
        let suiteName = "test.generalSettings.missionRun.geofenceShow.decode.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        defer { ud.removePersistentDomain(forName: suiteName) }

        let legacyJSON = #"{"defaultSimulationPlatform":"ardupilot"}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        ud.set(data, forKey: "guardian.generalSettings.v1")

        let store = GeneralSettingsStore(userDefaults: ud)
        XCTAssertTrue(store.missionControlShowMissionGeofencesOnMap)
    }
}
