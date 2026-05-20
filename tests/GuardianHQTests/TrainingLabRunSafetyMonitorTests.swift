import XCTest

@testable import GuardianCore

final class TrainingLabRunSafetyMonitorTests: XCTestCase {
    func test_inside_map_floor_uses_enu_bounds() {
        let origin = SimSpawnDefaults.default
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = origin.latitudeDeg
        hub.longitudeDeg = origin.longitudeDeg
        XCTAssertTrue(
            TrainingLabRunSafetyMonitor.isInsideMapFloor(
                hub: hub,
                mapGeodeticOrigin: origin,
                mapHalfExtentM: 500
            )
        )
    }

    func test_stuck_after_no_progress_window() {
        let plan = samplePlan()
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = plan.layout.start.latitudeDeg
        hub.longitudeDeg = plan.layout.start.longitudeDeg
        let started = Date().addingTimeInterval(-120)
        let stagnantSince = Date().addingTimeInterval(
            -(TrainingLabRunSafetyMonitor.stuckNoProgressWindowS + 5)
        )
        var track = TrainingLabRunSafetyMonitor.VehicleProgressTrack(
            bestAlongTrackM: 50,
            stagnantSince: stagnantSince
        )
        let route = TrainingLabTransitPathProgress.fallbackPath(for: plan)
        let violation = TrainingLabRunSafetyMonitor.stuckViolation(
            plan: plan,
            hub: hub,
            routePath: route,
            track: &track,
            runStartedAt: started,
            now: Date()
        )
        XCTAssertNotNil(violation)
        XCTAssertEqual(violation?.code, .executionFailed)
    }

    func test_running_session_tabs_omit_map() {
        XCTAssertFalse(TrainingLabPanelTab.runningSessionTabs.contains(.map))
        XCTAssertEqual(TrainingLabPanelTab.runningSessionTabs.count, 3)
    }

    private func samplePlan() -> TrainingLabRunVehiclePlan {
        let start = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        let goal = TrainingTaskPose(
            latitudeDeg: -35.001,
            longitudeDeg: 149.001,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        let slot = TrainingLabFormationSlotGeometry.Slot(
            squadID: UUID(),
            squadLabel: "Alpha",
            squadIndex: 0,
            slotIndex: 0,
            isPrimary: true,
            centerXM: 10,
            centerYM: 0,
            headingDeg: 0,
            widthM: 2,
            lengthM: 4,
            colorHex: "#f59e0b"
        )
        return TrainingLabRunVehiclePlan(
            entryID: UUID(),
            squadID: UUID(),
            squadIndex: 0,
            squadLabel: "Alpha",
            vehicleID: "v1",
            role: .learning,
            layout: TrainingTaskLayout(start: start, goal: goal),
            endSlot: slot,
            requiresStrictEndSlotBox: false
        )
    }
}
