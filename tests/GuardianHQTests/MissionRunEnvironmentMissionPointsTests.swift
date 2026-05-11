import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunEnvironmentMissionPointsTests: XCTestCase {

    func test_init_seedsRuntimePointsFromMission() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.missionPoints = [
            MissionPoint(pointId: "rally.alpha", label: "Rally A", kind: .rally, coordinate: RouteCoordinate(lat: 1, lon: 2)),
        ]
        let run = MissionRunEnvironment(mission: mission)
        XCTAssertEqual(run.runtimeMissionPoints.count, 1)
        XCTAssertEqual(run.runtimeMissionPoints[0].pointId, "rally.alpha")
    }

    func test_updateTemplate_whileSetup_reSyncsFromMission() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.missionPoints = [
            MissionPoint(pointId: "a", label: "A", kind: .rally, coordinate: RouteCoordinate()),
        ]
        let run = MissionRunEnvironment(mission: mission)
        XCTAssertEqual(run.runtimeMissionPoints.count, 1)

        var fresh = mission
        fresh.missionPoints.append(
            MissionPoint(pointId: "b", label: "B", kind: .extraction, coordinate: RouteCoordinate(lat: 3, lon: 4))
        )
        run.updateTemplate(fresh)
        XCTAssertEqual(run.runtimeMissionPoints.count, 2)
        XCTAssertEqual(Set(run.runtimeMissionPoints.map(\.pointId)), Set(["a", "b"]))
    }

    func test_updateTemplate_whileRunning_doesNotOverwriteRuntimeAdds() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.missionPoints = [
            MissionPoint(pointId: "tpl", label: "T", kind: .rally, coordinate: RouteCoordinate()),
        ]
        let run = MissionRunEnvironment(mission: mission)
        run.beginRun()
        let liveOnly = MissionPoint(pointId: "live.mre", label: "Live", kind: .extraction, coordinate: RouteCoordinate(lat: 9, lon: 9))
        XCTAssertTrue(run.applyRuntimeMissionPointCreate(liveOnly, source: "mre"))
        XCTAssertEqual(run.runtimeMissionPoints.count, 2)

        var refreshed = mission
        refreshed.name = "Renamed only"
        run.updateTemplate(refreshed)
        XCTAssertEqual(run.runtimeMissionPoints.count, 2)
        let liveRow = run.runtimeMissionPoints.first { $0.coordinate.lat == 9 && $0.coordinate.lon == 9 }
        XCTAssertEqual(liveRow?.pointId, "extraction.1")
        XCTAssertEqual(liveRow?.mapChipLabel, "EP:1")
    }

    func test_applyRuntimeMissionPointCreate_assignsSequentialSlugForChipLabel() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        run.beginRun()
        let p1 = MissionPoint(
            pointId: "x1",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 1)
        )
        XCTAssertTrue(run.applyRuntimeMissionPointCreate(p1, source: "operator"))
        XCTAssertEqual(run.runtimeMissionPoints[0].pointId, "rally.1")
        XCTAssertEqual(run.runtimeMissionPoints[0].mapChipLabel, "RP:1")

        let p2 = MissionPoint(
            pointId: "x2",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 2, lon: 2)
        )
        XCTAssertTrue(run.applyRuntimeMissionPointCreate(p2, source: "operator"))
        XCTAssertEqual(run.runtimeMissionPoints[1].pointId, "rally.2")
        XCTAssertEqual(run.runtimeMissionPoints[1].mapChipLabel, "RP:2")
    }

    func test_applyRuntimeMissionPointCreate_rejectsDuplicatePointId() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.missionPoints = [MissionPoint(pointId: "dup", label: "D", kind: .rally, coordinate: RouteCoordinate())]
        let run = MissionRunEnvironment(mission: mission)
        let second = MissionPoint(pointId: "dup", label: "Other", kind: .extraction, coordinate: RouteCoordinate(lat: 1, lon: 1))
        XCTAssertFalse(run.applyRuntimeMissionPointCreate(second))
        XCTAssertEqual(run.runtimeMissionPoints.count, 1)
    }

    func test_applyRuntimeMissionPointUpdate_mutatesRowAndLogs() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let pid = UUID()
        mission.missionPoints = [
            MissionPoint(id: pid, pointId: "x", label: "X", kind: .rally, coordinate: RouteCoordinate(), isClosed: false),
        ]
        let run = MissionRunEnvironment(mission: mission)
        XCTAssertTrue(
            run.applyRuntimeMissionPointUpdate(id: pid, source: "mre") { $0.label = "Y" }
        )
        XCTAssertEqual(run.runtimeMissionPoints.first?.label, "Y")
        XCTAssertEqual(run.events.last?.templateKey, MissionRunLogTemplateKey.missionPointRuntimeUpdated)
    }

    func test_applyRuntimeMissionPointUpdate_mutatesRowAndLogs() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let pid = UUID()
        mission.missionPoints = [
            MissionPoint(id: pid, pointId: "x", label: "X", kind: .rally, coordinate: RouteCoordinate(), isClosed: false),
        ]
        let run = MissionRunEnvironment(mission: mission)
        XCTAssertTrue(
            run.applyRuntimeMissionPointUpdate(id: pid, source: "mre") { $0.label = "Y" }
        )
        XCTAssertEqual(run.runtimeMissionPoints.first?.label, "Y")
        XCTAssertEqual(run.events.last?.templateKey, MissionRunLogTemplateKey.missionPointRuntimeUpdated)
    }

    func test_applyRuntimeMissionPointSetClosed_logsAndUpdates() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let pid = UUID()
        mission.missionPoints = [
            MissionPoint(id: pid, pointId: "x", label: "X", kind: .rally, coordinate: RouteCoordinate(), isClosed: false),
        ]
        let run = MissionRunEnvironment(mission: mission)
        XCTAssertTrue(run.applyRuntimeMissionPointSetClosed(id: pid, isClosed: true, source: "operator"))
        XCTAssertTrue(run.runtimeMissionPoints[0].isClosed)
        let lastKey = run.events.last?.templateKey
        XCTAssertEqual(lastKey, MissionRunLogTemplateKey.missionPointRuntimeClosedChanged)
    }
}
