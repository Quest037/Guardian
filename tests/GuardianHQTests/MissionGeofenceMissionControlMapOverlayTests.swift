import XCTest
@testable import GuardianHQ

@MainActor
final class MissionGeofenceMissionControlMapOverlayTests: XCTestCase {

    func test_geofenceGuardianMapOverlays_showOff_returnsEmpty() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 1, lon: 2))
        var task = MissionTask(name: "Alpha")
        task.geofences = [MissionGeofence.newPolygon(name: "Corridor", around: RouteCoordinate(lat: 3, lon: 4))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [missionFence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = false
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: nil,
            respectMapTaskIsolation: true
        )
        XCTAssertTrue(overlays.isEmpty)
    }

    func test_geofenceGuardianMapOverlays_withoutIsolation_includesMissionAndAllTasks() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var t1 = MissionTask(name: "A")
        t1.geofences = [MissionGeofence.newCircle(name: "Fa", center: RouteCoordinate(lat: 1, lon: 1))]
        var t2 = MissionTask(name: "B")
        t2.geofences = [MissionGeofence.newCircle(name: "Fb", center: RouteCoordinate(lat: 2, lon: 2))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t1, t2]),
            missionGeofences: [missionFence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = false
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: t2.id,
            respectMapTaskIsolation: true
        )
        let ids = Set(overlays.map(\.id))
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains(missionFence.id))
        XCTAssertTrue(ids.contains(t1.geofences[0].id))
        XCTAssertTrue(ids.contains(t2.geofences[0].id))
    }

    func test_geofenceGuardianMapOverlays_withIsolation_focusesSingleTaskPlusMission() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var t1 = MissionTask(name: "A")
        t1.geofences = [MissionGeofence.newCircle(name: "Fa", center: RouteCoordinate(lat: 1, lon: 1))]
        var t2 = MissionTask(name: "B")
        t2.geofences = [MissionGeofence.newCircle(name: "Fb", center: RouteCoordinate(lat: 2, lon: 2))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t1, t2]),
            missionGeofences: [missionFence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = true
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: t2.id,
            respectMapTaskIsolation: true
        )
        let ids = Set(overlays.map(\.id))
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(missionFence.id))
        XCTAssertTrue(ids.contains(t2.geofences[0].id))
    }

    func test_geofenceGuardianMapOverlays_withIsolation_noFocusedTask_missionWideOnly() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var t1 = MissionTask(name: "A")
        t1.geofences = [MissionGeofence.newCircle(name: "Fa", center: RouteCoordinate(lat: 1, lon: 1))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t1]),
            missionGeofences: [missionFence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = true
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: nil,
            respectMapTaskIsolation: true
        )
        XCTAssertEqual(overlays.count, 1)
        XCTAssertEqual(overlays.first?.id, missionFence.id)
    }

    func test_geofenceGuardianMapOverlays_respectIsolationFalse_showsAllTasksEvenWhenIsolateOn() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var t1 = MissionTask(name: "A")
        t1.geofences = [MissionGeofence.newCircle(name: "Fa", center: RouteCoordinate(lat: 1, lon: 1))]
        var t2 = MissionTask(name: "B")
        t2.geofences = [MissionGeofence.newCircle(name: "Fb", center: RouteCoordinate(lat: 2, lon: 2))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t1, t2]),
            missionGeofences: [missionFence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = true
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: nil,
            respectMapTaskIsolation: false
        )
        XCTAssertEqual(overlays.count, 3)
    }

    func test_geofenceGuardianMapOverlays_withRun_includesMissionWideAugmentation() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var task = MissionTask(name: "A")
        task.geofences = [MissionGeofence.newCircle(name: "Ta", center: RouteCoordinate(lat: 1, lon: 1))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [missionFence]
        )
        let run = MissionRunEnvironment(mission: mission)
        let aug = MissionGeofence.newCircle(name: "RunM", center: RouteCoordinate(lat: 5, lon: 5))
        _ = run.updateMissionGeofenceAugmentation([aug], credential: .localOperator(callsign: "op"))
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = false
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: task.id,
            respectMapTaskIsolation: true,
            run: run
        )
        let ids = Set(overlays.map(\.id))
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains(aug.id))
    }

    func test_geofenceGuardianMapOverlays_withRun_isolation_includesFocusedTaskAugmentationAndSlots() {
        let missionFence = MissionGeofence.newCircle(name: "Site", center: RouteCoordinate(lat: 0, lon: 0))
        var t1 = MissionTask(name: "A")
        t1.geofences = [MissionGeofence.newCircle(name: "Fa", center: RouteCoordinate(lat: 1, lon: 1))]
        var t2 = MissionTask(name: "B")
        t2.geofences = [MissionGeofence.newCircle(name: "Fb", center: RouteCoordinate(lat: 2, lon: 2))]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [t1, t2]),
            missionGeofences: [missionFence]
        )
        let rid = UUID()
        let slotFence = MissionGeofence.newCircle(name: "Slot", center: RouteCoordinate(lat: 9, lon: 9))
        let asn = MissionRunAssignment(
            taskId: t2.id,
            rosterDeviceId: rid,
            slotName: "P1",
            policies: MissionRunAssignmentPolicies(geofenceAugmentation: [slotFence])
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [asn])
        let taskAug = MissionGeofence.newCircle(name: "RunT", center: RouteCoordinate(lat: 8, lon: 8))
        _ = run.updateTaskGeofenceAugmentation(taskID: t2.id, [taskAug], credential: .localOperator(callsign: "op"))
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = true
        let overlays = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: t2.id,
            respectMapTaskIsolation: true,
            run: run
        )
        let ids = Set(overlays.map(\.id))
        XCTAssertEqual(ids.count, 4)
        XCTAssertTrue(ids.contains(missionFence.id))
        XCTAssertTrue(ids.contains(t2.geofences[0].id))
        XCTAssertTrue(ids.contains(taskAug.id))
        XCTAssertTrue(ids.contains(slotFence.id))
        XCTAssertFalse(ids.contains(t1.geofences[0].id))
    }

    func test_mapSelectionFenceID_marksOverlayAuthoringSelected() {
        let fence = MissionGeofence.newCircle(name: "Pick", center: RouteCoordinate(lat: 1, lon: 2))
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: []),
            missionGeofences: [fence]
        )
        var settings = MissionRunOperatorDisplaySettings.default
        settings.showMissionGeofencesOnMap = true
        settings.isolateLiveMapToSelectedTask = false
        let withoutSel = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: nil,
            respectMapTaskIsolation: false,
            run: nil,
            mapSelectionFenceID: nil
        )
        let withSel = mission.geofenceGuardianMapOverlaysForMissionControl(
            operatorSettings: settings,
            mapFocusedTaskID: nil,
            respectMapTaskIsolation: false,
            run: nil,
            mapSelectionFenceID: fence.id
        )
        XCTAssertEqual(withoutSel.count, 1)
        XCTAssertFalse(withoutSel[0].isAuthoringMapSelected)
        XCTAssertEqual(withSel.count, 1)
        XCTAssertTrue(withSel[0].isAuthoringMapSelected)
    }
}
