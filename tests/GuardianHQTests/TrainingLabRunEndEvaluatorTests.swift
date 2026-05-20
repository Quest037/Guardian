import XCTest

@testable import GuardianCore

final class TrainingLabRunEndEvaluatorTests: XCTestCase {
    func test_vehicle_center_inside_slot() {
        let slot = TrainingLabFormationSlotGeometry.Slot(
            squadID: UUID(),
            squadLabel: "Alpha",
            squadIndex: 0,
            slotIndex: 0,
            isPrimary: true,
            centerXM: 10,
            centerYM: 5,
            headingDeg: 0,
            widthM: 2,
            lengthM: 4,
            colorHex: "#f59e0b"
        )
        XCTAssertTrue(
            TrainingLabFormationSlotGeometry.vehicleCenterInsideSlot(
                vehicleXM: 10,
                vehicleYM: 5,
                slot: slot
            )
        )
        XCTAssertFalse(
            TrainingLabFormationSlotGeometry.vehicleCenterInsideSlot(
                vehicleXM: 13,
                vehicleYM: 5,
                slot: slot
            )
        )
    }

    func test_strict_end_slot_requires_box_not_centre_arrival() {
        let origin = SimSpawnDefaults.default
        let endSlot = TrainingLabFormationSlotGeometry.Slot(
            squadID: UUID(),
            squadLabel: "Alpha",
            squadIndex: 0,
            slotIndex: 0,
            isPrimary: true,
            centerXM: 0,
            centerYM: 0,
            headingDeg: 0,
            widthM: 2,
            lengthM: 4,
            colorHex: "#f59e0b"
        )
        let goal = TrainingEnvironmentGeodesy.taskPose(
            environmentPose: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            origin: origin
        )
        // Hub at goal centre but strict mode still needs inside box — centre is inside.
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = goal.latitudeDeg
        hub.longitudeDeg = goal.longitudeDeg
        hub.headingDeg = 0

        let outcome = TrainingLabRunEndEvaluator.evaluate(
            entryID: UUID(),
            vehicleID: "v1",
            hub: hub,
            goal: goal,
            episodeDurationS: 1,
            endSlot: endSlot,
            mapGeodeticOrigin: origin,
            requiresStrictEndSlotBox: true
        )
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.insideEndSlotBox, true)
    }

    func test_auto_end_formation_uses_centre_arrival() {
        let origin = SimSpawnDefaults.default
        let goal = TrainingTaskPose(
            latitudeDeg: origin.latitudeDeg,
            longitudeDeg: origin.longitudeDeg,
            headingDeg: 0,
            absoluteAltitudeM: origin.altitudeM
        )
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = goal.latitudeDeg
        hub.longitudeDeg = goal.longitudeDeg
        hub.headingDeg = 0

        let endSlot = TrainingLabFormationSlotGeometry.Slot(
            squadID: UUID(),
            squadLabel: "Alpha",
            squadIndex: 0,
            slotIndex: 0,
            isPrimary: true,
            centerXM: 0,
            centerYM: 0,
            headingDeg: 0,
            widthM: 2,
            lengthM: 4,
            colorHex: "#f59e0b"
        )

        let outcome = TrainingLabRunEndEvaluator.evaluate(
            entryID: UUID(),
            vehicleID: "v1",
            hub: hub,
            goal: goal,
            episodeDurationS: 1,
            endSlot: endSlot,
            mapGeodeticOrigin: origin,
            requiresStrictEndSlotBox: false
        )
        XCTAssertTrue(outcome.succeeded)
        XCTAssertNil(outcome.insideEndSlotBox)
    }
}
