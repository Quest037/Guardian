import XCTest
@testable import GuardianCore

@MainActor
final class TrainingLabTransitRouteOverlayTests: XCTestCase {
    private func samplePlan(vehicleID: String = "sysid:1") -> TrainingLabRunVehiclePlan {
        TrainingLabRunVehiclePlan(
            entryID: UUID(),
            squadID: UUID(),
            squadIndex: 0,
            squadLabel: "Alpha",
            vehicleID: vehicleID,
            role: .learning,
            layout: TrainingTaskLayout(
                start: TrainingTaskPose(latitudeDeg: 47.3977, longitudeDeg: 8.5449, headingDeg: 0, absoluteAltitudeM: 488),
                goal: TrainingTaskPose(latitudeDeg: 47.3978, longitudeDeg: 8.5450, headingDeg: 90, absoluteAltitudeM: 488)
            ),
            endSlot: TrainingLabFormationSlotGeometry.Slot(
                squadID: UUID(),
                squadLabel: "Alpha",
                squadIndex: 0,
                slotIndex: 0,
                isPrimary: true,
                centerXM: 10,
                centerYM: 20,
                headingDeg: 90,
                widthM: 2,
                lengthM: 3,
                colorHex: "#f59e0b"
            ),
            requiresStrictEndSlotBox: false
        )
    }

    func test_makePaths_converts_resolved_route_to_enu_with_lift() {
        let origin = SimSpawnDefaults(
            latitudeDeg: 47.3977,
            longitudeDeg: 8.5449,
            altitudeM: 488.0
        )
        let resolved: [String: TrainingLabTransitMotion.PathResolution] = [
            "sysid:1": TrainingLabTransitMotion.PathResolution(
                points: [
                    RouteCoordinate(lat: 47.39775, lon: 8.54490),
                    RouteCoordinate(lat: 47.39780, lon: 8.54500),
                    RouteCoordinate(lat: 47.39785, lon: 8.54510),
                ],
                source: .nav2
            ),
        ]

        let paths = TrainingLabTransitRouteOverlay.makePaths(
            plans: [samplePlan()],
            resolvedByVehicleID: resolved,
            mapGeodeticOrigin: origin
        )

        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].id, "sysid:1")
        XCTAssertEqual(paths[0].pathSource, .nav2)
        XCTAssertEqual(paths[0].points.count, 3)
        XCTAssertEqual(paths[0].points[0].zM, 0.14, accuracy: 1e-6)
        XCTAssertNotEqual(paths[0].points[0].xM, 0)
        XCTAssertNotEqual(paths[0].points[0].yM, 0)
    }

    func test_makePaths_skips_single_point_or_missing_resolution() {
        let plan = samplePlan(vehicleID: "sysid:2")
        let resolved: [String: TrainingLabTransitMotion.PathResolution] = [
            "sysid:2": TrainingLabTransitMotion.PathResolution(
                points: [RouteCoordinate(lat: 47.0, lon: 8.0)],
                source: .geodesicFallback
            ),
        ]

        XCTAssertTrue(
            TrainingLabTransitRouteOverlay.makePaths(
                plans: [plan],
                resolvedByVehicleID: resolved,
                mapGeodeticOrigin: .default
            ).isEmpty
        )
    }
}
