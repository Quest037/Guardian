import XCTest

@testable import GuardianHQ

final class MissionPointMissionControlLiveMapFilterTests: XCTestCase {
    func test_filteredForMissionControlLiveMap_noTaskFocus_returnsAll() {
        let taskA = UUID()
        let taskB = UUID()
        let points = [
            MissionPoint(pointId: "rally.1", label: "", kind: .rally, coordinate: RouteCoordinate(lat: 1, lon: 2), taskID: nil),
            MissionPoint(pointId: "rally.2", label: "", kind: .rally, coordinate: RouteCoordinate(lat: 3, lon: 4), taskID: taskA),
            MissionPoint(pointId: "extraction.1", label: "", kind: .extraction, coordinate: RouteCoordinate(lat: 5, lon: 6), taskID: taskB),
        ]
        let filtered = MissionPoint.filteredForMissionControlLiveMap(points, focusedTaskID: nil)
        XCTAssertEqual(filtered.count, 3)
    }

    func test_filteredForMissionControlLiveMap_taskFocus_includesMissionWide_andScopedRows() {
        let focused = UUID()
        let otherTask = UUID()
        let missionWide = MissionPoint(
            pointId: "rally.1",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 1),
            taskID: nil
        )
        let scopedMatch = MissionPoint(
            pointId: "rally.2",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 2, lon: 2),
            taskID: focused
        )
        let scopedOther = MissionPoint(
            pointId: "extraction.1",
            label: "",
            kind: .extraction,
            coordinate: RouteCoordinate(lat: 3, lon: 3),
            taskID: otherTask
        )
        let filtered = MissionPoint.filteredForMissionControlLiveMap(
            [missionWide, scopedMatch, scopedOther],
            focusedTaskID: focused
        )
        XCTAssertEqual(Set(filtered.map(\.id)), Set([missionWide.id, scopedMatch.id]))
    }
}
