import XCTest
@testable import GuardianCore

final class MissionPointTests: XCTestCase {

    private func missionJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func missionJSONEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    func test_catchment_clampsToRange() {
        let low = MissionPoint(
            pointId: "rally.a",
            label: "Rally A",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 2),
            catchmentRadiusM: 0.5
        )
        XCTAssertEqual(low.catchmentRadiusM, 1)

        let high = MissionPoint(
            pointId: "rally.b",
            label: "Rally B",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 2),
            catchmentRadiusM: 5000
        )
        XCTAssertEqual(high.catchmentRadiusM, 1000)

        let mid = MissionPoint(
            pointId: "rally.c",
            label: "Rally C",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 2),
            catchmentRadiusM: 25
        )
        XCTAssertEqual(mid.catchmentRadiusM, 25)
    }

    func test_mission_decode_withoutMissionPoints_isEmpty() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000099","name":"M","description":"","type":"mobile","isArchived":false,"count":0,"duration":0,"deviceIDs":[],"spaces":[],"routeMacro":{"version":2,"paths":[]},"createdAt":"2020-01-01T00:00:00Z","cardThumbnailVersion":0}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let mission = try missionJSONDecoder().decode(Mission.self, from: data)
        XCTAssertTrue(mission.missionPoints.isEmpty)
    }

    func test_mission_roundTrip_missionPoints() throws {
        let p = MissionPoint(
            pointId: "extraction.hold",
            label: "Extraction C",
            kind: .extraction,
            coordinate: RouteCoordinate(lat: -33.8, lon: 151.2),
            taskID: nil,
            catchmentRadiusM: 10,
            isClosed: false
        )
        var mission = Mission(name: "P", description: "", type: .mobile)
        mission.missionPoints = [p]
        let data = try missionJSONEncoder().encode(mission)
        let decoded = try missionJSONDecoder().decode(Mission.self, from: data)
        XCTAssertEqual(decoded.missionPoints.count, 1)
        XCTAssertEqual(decoded.missionPoints[0].pointId, "extraction.hold")
        XCTAssertEqual(decoded.missionPoints[0].kind, .extraction)
        XCTAssertEqual(decoded.missionPoints[0].catchmentRadiusM, 10)
        XCTAssertNil(decoded.missionPoints[0].taskID)
    }

    func test_removeMissionPoints_forRemovedTaskID() {
        let taskA = UUID()
        let taskB = UUID()
        var mission = Mission(name: "T", description: "", type: .mobile)
        mission.missionPoints = [
            MissionPoint(pointId: "r.1", label: "Wide", kind: .rally, coordinate: RouteCoordinate(), taskID: nil),
            MissionPoint(pointId: "r.2", label: "A", kind: .rally, coordinate: RouteCoordinate(), taskID: taskA),
            MissionPoint(pointId: "r.3", label: "B", kind: .rally, coordinate: RouteCoordinate(), taskID: taskB),
        ]
        mission.removeMissionPoints(forRemovedTaskID: taskA)
        XCTAssertEqual(mission.missionPoints.count, 2)
        XCTAssertEqual(Set(mission.missionPoints.map(\.pointId)), Set(["r.1", "r.3"]))
    }

    func test_mapChipLabel_usesKindPrefixAndOrdinal() {
        let rally = MissionPoint(pointId: "rally.1", label: "", kind: .rally, coordinate: RouteCoordinate())
        XCTAssertEqual(rally.mapChipLabel, "RP:1")
        XCTAssertEqual(rally.mapGlyphDigit, "1")
        let ext = MissionPoint(pointId: "extraction.2", label: "", kind: .extraction, coordinate: RouteCoordinate())
        XCTAssertEqual(ext.mapChipLabel, "EP:2")
        XCTAssertEqual(ext.mapGlyphDigit, "2")
    }

    func test_filteredForMissionControlLiveMap_nilFocus_returnsAll() {
        let taskA = UUID()
        let pts = [
            MissionPoint(pointId: "r.1", label: "", kind: .rally, coordinate: RouteCoordinate(), taskID: nil),
            MissionPoint(pointId: "r.2", label: "", kind: .rally, coordinate: RouteCoordinate(), taskID: taskA),
        ]
        let out = MissionPoint.filteredForMissionControlLiveMap(pts, focusedTaskID: nil)
        XCTAssertEqual(out.count, 2)
    }

    func test_filteredForMissionControlLiveMap_focus_missionWidePlusMatchingTask() {
        let taskA = UUID()
        let taskB = UUID()
        let wide = MissionPoint(pointId: "r.1", label: "", kind: .rally, coordinate: RouteCoordinate(), taskID: nil)
        let a = MissionPoint(pointId: "r.2", label: "", kind: .rally, coordinate: RouteCoordinate(), taskID: taskA)
        let b = MissionPoint(pointId: "r.3", label: "", kind: .rally, coordinate: RouteCoordinate(), taskID: taskB)
        let out = MissionPoint.filteredForMissionControlLiveMap([wide, a, b], focusedTaskID: taskA)
        XCTAssertEqual(Set(out.map(\.pointId)), Set(["r.1", "r.2"]))
    }

    func test_renumberMissionPointSlugsByListOrder() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        mission.missionPoints = [
            MissionPoint(id: idA, pointId: "legacy", label: "x", kind: .rally, coordinate: RouteCoordinate(lat: 1, lon: 1)),
            MissionPoint(id: idB, pointId: "legacy2", label: "y", kind: .rally, coordinate: RouteCoordinate(lat: 2, lon: 2)),
            MissionPoint(id: idC, pointId: "legacy3", label: "z", kind: .extraction, coordinate: RouteCoordinate(lat: 3, lon: 3)),
        ]
        mission.renumberMissionPointSlugsByListOrder()
        XCTAssertEqual(mission.missionPoints.map(\.pointId), ["rally.1", "rally.2", "extraction.1"])
        XCTAssertEqual(mission.missionPoints.map(\.label), ["", "", ""])
        XCTAssertEqual(mission.missionPoints.map(\.id), [idA, idB, idC])
    }

    func test_mapChipLabel_nonNumericSlug_suffixShowsPlaceholder() {
        let rally = MissionPoint(pointId: "rally.alpha", label: "A", kind: .rally, coordinate: RouteCoordinate())
        XCTAssertEqual(rally.mapChipLabel, "RP:?")
        let ext = MissionPoint(pointId: "hold", label: "H", kind: .extraction, coordinate: RouteCoordinate())
        XCTAssertEqual(ext.mapChipLabel, "EP:?")
    }

    func test_makeUniquePointId_avoidsCollisions() {
        let existing: Set<String> = ["rally.1", "rally.2", "extraction.1"]
        XCTAssertEqual(MissionPoint.makeUniquePointId(kind: .rally, existing: existing), "rally.3")
        XCTAssertEqual(MissionPoint.makeUniquePointId(kind: .extraction, existing: existing), "extraction.2")
    }

    func test_duplicatedForClonedMission_newRowId() {
        let original = MissionPoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            pointId: "rally.alpha",
            label: "Rally A",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 3, lon: 4)
        )
        let copy = original.duplicatedForClonedMission()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.pointId, original.pointId)
        XCTAssertEqual(copy.coordinate.lat, original.coordinate.lat)
    }
}
