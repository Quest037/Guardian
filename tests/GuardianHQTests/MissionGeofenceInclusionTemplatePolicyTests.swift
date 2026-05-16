import XCTest

@testable import GuardianHQ

final class MissionGeofenceInclusionTemplatePolicyTests: XCTestCase {
    private let util = MissionTemplateGeofenceUtilities()

    func test_inclusionPolicy_ok_missionWideOnly() {
        let t = MissionTask(name: "Alpha")
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [
                MissionGeofence(name: "A", boundary: .inclusion, shape: .circle),
            ]
        )
        XCTAssertNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_inclusionPolicy_ok_taskOnly() {
        var t = MissionTask(name: "Alpha")
        t.geofences = [
            MissionGeofence(name: "T", boundary: .inclusion, shape: .circle),
        ]
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t])
        )
        XCTAssertNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_inclusionPolicy_rejects_twoMissionWideInclusions() {
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: []),
            missionGeofences: [
                MissionGeofence(name: "A", boundary: .inclusion, shape: .circle),
                MissionGeofence(name: "B", boundary: .inclusion, shape: .circle),
            ]
        )
        XCTAssertNotNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_inclusionPolicy_rejects_missionWidePlusTaskInclusion() {
        var t = MissionTask(name: "Route")
        t.geofences = [MissionGeofence(name: "Task in", boundary: .inclusion, shape: .circle)]
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "Mission in", boundary: .inclusion, shape: .circle)]
        )
        let msg = util.inclusionConstraintViolationMessage(for: m)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.localizedCaseInsensitiveContains("mission-wide"))
        XCTAssertTrue(msg!.localizedCaseInsensitiveContains("task"))
    }

    func test_inclusionPolicy_rejects_twoTaskInclusions() {
        var t = MissionTask(name: "Route")
        t.geofences = [
            MissionGeofence(name: "A", boundary: .inclusion, shape: .circle),
            MissionGeofence(name: "B", boundary: .inclusion, shape: .circle),
        ]
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t]))
        XCTAssertNotNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_inclusionPolicy_allows_missionInclusion_with_taskExclusionsOnly() {
        var t = MissionTask(name: "Route")
        t.geofences = [
            MissionGeofence(name: "E1", boundary: .exclusion, shape: .circle),
            MissionGeofence(name: "E2", boundary: .exclusion, shape: .circle),
        ]
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "MIn", boundary: .inclusion, shape: .circle)]
        )
        XCTAssertNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_inclusionPolicy_allows_multipleTaskExclusions_withMissionInclusion() {
        var t = MissionTask(name: "Route")
        t.geofences = [
            MissionGeofence(name: "E1", boundary: .exclusion, shape: .circle),
            MissionGeofence(name: "E2", boundary: .exclusion, shape: .circle),
        ]
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "MIn", boundary: .inclusion, shape: .circle)]
        )
        XCTAssertNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_exclusionRequiresInclusion_rejects_taskExclusionsOnly() {
        var t = MissionTask(name: "Route")
        t.geofences = [MissionGeofence(name: "E1", boundary: .exclusion, shape: .circle)]
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t]))
        XCTAssertNotNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_exclusionRequiresInclusion_rejects_missionWideExclusionsOnly_noTasks() {
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: []),
            missionGeofences: [MissionGeofence(name: "X", boundary: .exclusion, shape: .circle)]
        )
        XCTAssertNotNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_exclusionRequiresInclusion_ok_missionExclusionPlusTaskInclusion() {
        var t = MissionTask(name: "Route")
        t.geofences = [
            MissionGeofence(name: "TIn", boundary: .inclusion, shape: .circle),
            MissionGeofence(name: "E1", boundary: .exclusion, shape: .circle),
        ]
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "MX", boundary: .exclusion, shape: .circle)]
        )
        XCTAssertNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_exclusionRequiresInclusion_rejects_missionExclusion_taskHasNoFences() {
        let t = MissionTask(name: "Route")
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "MX", boundary: .exclusion, shape: .circle)]
        )
        XCTAssertNotNil(util.inclusionConstraintViolationMessage(for: m))
    }

    func test_defaultBoundaryForNewMissionWideFence_inclusionWhenNone() {
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: []))
        XCTAssertEqual(util.defaultBoundaryForNewMissionWideFence(in: m), .inclusion)
    }

    func test_defaultBoundaryForNewMissionWideFence_exclusionWhenMissionWideInclusionExists() {
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: []),
            missionGeofences: [MissionGeofence(name: "A", boundary: .inclusion, shape: .circle)]
        )
        XCTAssertEqual(util.defaultBoundaryForNewMissionWideFence(in: m), .exclusion)
    }

    func test_defaultBoundaryForNewMissionWideFence_exclusionWhenTaskInclusionExists() {
        var t = MissionTask(name: "Route")
        t.geofences = [MissionGeofence(name: "T", boundary: .inclusion, shape: .circle)]
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t]))
        XCTAssertEqual(util.defaultBoundaryForNewMissionWideFence(in: m), .exclusion)
    }

    func test_defaultBoundaryForNewTaskScopedFence_inclusionWhenTaskHasNone() {
        let t = MissionTask(name: "Route")
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t]))
        XCTAssertEqual(util.defaultBoundaryForNewTaskScopedFence(taskID: t.id, in: m), .inclusion)
    }

    func test_defaultBoundaryForNewTaskScopedFence_exclusionWhenTaskAlreadyHasInclusion() {
        var t = MissionTask(name: "Route")
        t.geofences = [MissionGeofence(name: "A", boundary: .inclusion, shape: .circle)]
        let m = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t]))
        XCTAssertEqual(util.defaultBoundaryForNewTaskScopedFence(taskID: t.id, in: m), .exclusion)
    }

    func test_defaultBoundaryForNewTaskScopedFence_exclusionWhenMissionWideInclusionExists() {
        let t = MissionTask(name: "Route")
        let m = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t]),
            missionGeofences: [MissionGeofence(name: "M", boundary: .inclusion, shape: .circle)]
        )
        XCTAssertEqual(util.defaultBoundaryForNewTaskScopedFence(taskID: t.id, in: m), .exclusion)
    }
}
