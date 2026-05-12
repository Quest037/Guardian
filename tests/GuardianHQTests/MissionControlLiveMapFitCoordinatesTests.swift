import XCTest

@testable import GuardianHQ

final class MissionControlLiveMapFitCoordinatesTests: XCTestCase {
    func test_isUsableWgs84ForMapFit_rejectsOriginAndNonFinite() {
        XCTAssertFalse(MissionControlLiveMapFitCoordinates.isUsableWgs84ForMapFit(lat: 0, lon: 0))
        XCTAssertFalse(MissionControlLiveMapFitCoordinates.isUsableWgs84ForMapFit(lat: .nan, lon: 1))
        XCTAssertTrue(MissionControlLiveMapFitCoordinates.isUsableWgs84ForMapFit(lat: -33.8, lon: 151.2))
    }

    func test_taskTriageFitCoordinates_includesWaypointsTaskScopedPointsAndVehicles() {
        let taskID = UUID()
        let otherTask = UUID()
        let wp = RouteWaypoint(coord: RouteCoordinate(lat: 1, lon: 2), pathRole: .anchor)
        let wpUnset = RouteWaypoint(coord: RouteCoordinate(lat: 0, lon: 0), pathRole: .anchor)
        let missionWide = MissionPoint(
            pointId: "rally.1",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 9, lon: 9),
            taskID: nil
        )
        let taskPoint = MissionPoint(
            pointId: "rally.2",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 3, lon: 4),
            taskID: taskID
        )
        let otherTaskPoint = MissionPoint(
            pointId: "extraction.1",
            label: "",
            kind: .extraction,
            coordinate: RouteCoordinate(lat: 5, lon: 6),
            taskID: otherTask
        )
        let coords = MissionControlLiveMapFitCoordinates.taskTriageFitCoordinates(
            taskWaypoints: [wp, wpUnset],
            taskID: taskID,
            runtimeMissionPoints: [missionWide, taskPoint, otherTaskPoint],
            rosterVehicleHubCoordinates: [(7, 8), (0, 0)]
        )
        let set = Set(coords.map { "\($0.0),\($0.1)" })
        XCTAssertEqual(set, ["1.0,2.0", "3.0,4.0", "7.0,8.0"])
        XCTAssertEqual(coords.count, 3)
    }
}
