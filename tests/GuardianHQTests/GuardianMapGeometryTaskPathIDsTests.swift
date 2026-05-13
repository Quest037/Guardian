import XCTest
@testable import GuardianHQ

final class GuardianMapGeometryTaskPathIDsTests: XCTestCase {

    func test_empty_geometry_has_empty_task_path_ids() {
        XCTAssertTrue(GuardianRouteMapGeometry.empty.taskPathIDs.isEmpty)
        XCTAssertTrue(GuardianRouteMapGeometry.empty.allTasksCoords.isEmpty)
    }

    func test_task_path_ids_participate_in_equatable() {
        let id = UUID()
        let coord = RouteCoordinate(lat: 1, lon: 2)
        let base = GuardianRouteMapGeometry(
            home: nil,
            allTasksCoords: [[coord]],
            taskPathIDs: [id],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false
        )
        let same = GuardianRouteMapGeometry(
            home: nil,
            allTasksCoords: [[coord]],
            taskPathIDs: [id],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false
        )
        let otherID = GuardianRouteMapGeometry(
            home: nil,
            allTasksCoords: [[coord]],
            taskPathIDs: [UUID()],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false
        )
        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, otherID)
    }

    func test_mcs_reserve_pool_home_armed_participates_in_equatable() {
        let coord = RouteCoordinate(lat: 1, lon: 2)
        let id = UUID()
        let off = GuardianRouteMapGeometry(
            home: nil,
            allTasksCoords: [[coord]],
            taskPathIDs: [id],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false
        )
        let on = GuardianRouteMapGeometry(
            home: nil,
            allTasksCoords: [[coord]],
            taskPathIDs: [id],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: true
        )
        XCTAssertNotEqual(off, on)
    }
}
