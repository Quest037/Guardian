import XCTest
@testable import GuardianCore

final class TrainingLabRunPathPlanningTests: XCTestCase {
    func test_routeLogLine_includes_source_and_point_count() {
        let plan = TrainingLabRunVehiclePlan(
            entryID: UUID(),
            squadID: UUID(),
            squadIndex: 0,
            squadLabel: "Alpha",
            vehicleID: "sysid:1",
            role: .learning,
            layout: TrainingTaskLayout(
                start: TrainingTaskPose(latitudeDeg: -35, longitudeDeg: 149, headingDeg: 0, absoluteAltitudeM: 0),
                goal: TrainingTaskPose(latitudeDeg: -35.001, longitudeDeg: 149.001, headingDeg: 90, absoluteAltitudeM: 0)
            ),
            endSlot: TrainingLabFormationSlotGeometry.Slot(
                squadID: UUID(),
                squadLabel: "Alpha",
                squadIndex: 0,
                slotIndex: 0,
                isPrimary: true,
                centerXM: 0,
                centerYM: 0,
                headingDeg: 0,
                widthM: 2,
                lengthM: 3,
                colorHex: "#f59e0b"
            ),
            requiresStrictEndSlotBox: false
        )
        let path = TrainingLabTransitMotion.PathResolution(
            points: [
                RouteCoordinate(lat: -35, lon: 149),
                RouteCoordinate(lat: -35.001, lon: 149.001),
            ],
            source: .nav2
        )
        let line = TrainingLabRunPathPlanning.routeLogLine(plan: plan, path: path)
        XCTAssertTrue(line.contains("nav2"))
        XCTAssertTrue(line.contains("2 pt"))
        XCTAssertTrue(line.contains("Alpha"))
    }
}
