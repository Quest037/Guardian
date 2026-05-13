import XCTest
@testable import GuardianHQ

final class MissionTemplateGeofencePlanningMergeTests: XCTestCase {

    func test_effectiveTemplateGeofences_missionWideThenTaskOrder() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 1, lon: 2))
        var task = MissionTask(name: "Alpha")
        let taskFence = MissionGeofence.newPolygon(name: "Corridor", around: RouteCoordinate(lat: 3, lon: 4))
        task.geofences = [taskFence]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [missionFence]
        )
        let u = MissionTemplateGeofenceUtilities()
        let merged = u.effectiveTemplateGeofencesForPlanning(taskID: task.id, mission: mission)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].id, missionFence.id)
        XCTAssertEqual(merged[1].id, taskFence.id)
    }

    func test_effectiveTemplateGeofences_unknownTaskID_returnsMissionWideOnly() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var task = MissionTask(name: "Alpha")
        task.geofences = [MissionGeofence.newCircle(name: "T", center: RouteCoordinate(lat: 9, lon: 9))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [missionFence]
        )
        let u = MissionTemplateGeofenceUtilities()
        let merged = u.effectiveTemplateGeofencesForPlanning(taskID: UUID(), mission: mission)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, missionFence.id)
    }
}
