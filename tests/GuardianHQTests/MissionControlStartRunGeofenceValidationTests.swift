import XCTest
@testable import GuardianCore

@MainActor
final class MissionControlStartRunGeofenceValidationTests: XCTestCase {

    func test_firstContainingExclusion_detects_point_inside_polygon() {
        let fence = MissionGeofence(
            id: UUID(),
            name: "Keep-out",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: 0, lon: 0),
                RouteCoordinate(lat: 0, lon: 0.002),
                RouteCoordinate(lat: 0.002, lon: 0.002),
                RouteCoordinate(lat: 0.002, lon: 0),
            ]
        )
        let inside = RouteCoordinate(lat: 0.001, lon: 0.001)
        let outside = RouteCoordinate(lat: 0.01, lon: 0.01)
        XCTAssertEqual(
            MissionControlStartRunGeofenceValidationUtilities.firstContainingExclusion(
                coordinate: inside,
                geofences: [fence]
            )?.name,
            "Keep-out"
        )
        XCTAssertNil(
            MissionControlStartRunGeofenceValidationUtilities.firstContainingExclusion(
                coordinate: outside,
                geofences: [fence]
            )
        )
    }

    func test_exclusionViolations_uses_launch_override_without_hub() {
        let taskID = UUID()
        let assignmentID = UUID()
        let exclusion = MissionGeofence(
            id: UUID(),
            name: "Box",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: 0, lon: 0),
                RouteCoordinate(lat: 0, lon: 0.002),
                RouteCoordinate(lat: 0.002, lon: 0.002),
                RouteCoordinate(lat: 0.002, lon: 0),
            ]
        )
        var task = MissionTask(id: taskID, name: "Task 1")
        task.geofences = [exclusion]
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            id: assignmentID,
            taskId: taskID,
            rosterDeviceId: UUID(),
            slotName: "Alpha",
            attachedFleetVehicleToken: "sim:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])

        let violations = MissionControlStartRunGeofenceValidationUtilities.exclusionViolations(
            run: run,
            mission: mission,
            fleetLink: FleetLinkService(),
            launchCoordinateOverrides: [assignmentID: RouteCoordinate(lat: 0.001, lon: 0.001)],
            resolveVehicleID: { _ in nil }
        )
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations[0].assignmentID, assignmentID)
        XCTAssertTrue(
            MissionControlStartRunGeofenceValidationUtilities.failureDetail(for: violations[0])
                .contains("Start run blocked")
        )
    }

    func test_exclusionViolations_skips_slot_without_position() {
        let taskID = UUID()
        let assignmentID = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [MissionTask(id: taskID, name: "Task 1")])
        )
        let assignment = MissionRunAssignment(
            id: assignmentID,
            taskId: taskID,
            rosterDeviceId: UUID(),
            slotName: "Alpha",
            attachedFleetVehicleToken: "sim:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])

        let violations = MissionControlStartRunGeofenceValidationUtilities.exclusionViolations(
            run: run,
            mission: mission,
            fleetLink: FleetLinkService(),
            launchCoordinateOverrides: [:],
            resolveVehicleID: { _ in nil }
        )
        XCTAssertTrue(violations.isEmpty)
    }
}
