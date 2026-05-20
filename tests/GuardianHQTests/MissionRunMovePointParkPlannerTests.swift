import XCTest
@testable import GuardianCore

final class MissionRunMovePointParkPlannerTests: XCTestCase {

    func test_resolvedVehicleYawDeg_prefersHeadingOverYaw() {
        XCTAssertEqual(
            MissionRunMovePointParkPlanner.resolvedVehicleYawDeg(headingDeg: 90, yawDeg: 12),
            90
        )
        XCTAssertEqual(
            MissionRunMovePointParkPlanner.resolvedVehicleYawDeg(headingDeg: nil, yawDeg: 45),
            45
        )
        XCTAssertEqual(
            MissionRunMovePointParkPlanner.resolvedVehicleYawDeg(headingDeg: nil, yawDeg: nil),
            0
        )
    }

    func test_procedureLogSummary_usesMapChipLabel() {
        let p = MissionPoint(
            pointId: "rally.2",
            label: "North",
            kind: .rally,
            coordinate: RouteCoordinate(lat: 1, lon: 2),
            taskID: nil,
            isClosed: false
        )
        XCTAssertEqual(
            MissionRunMovePointParkPlanner.procedureLogSummary(for: p),
            "Move to rally point [RP:2]"
        )
    }

    func test_nearest_prefersOpenSameTaskOrMissionWide_ignoresClosedAndOtherTask() throws {
        let taskA = UUID()
        let taskB = UUID()
        let points: [MissionPoint] = [
            MissionPoint(
                pointId: "rally.1",
                label: "onA",
                kind: .rally,
                coordinate: RouteCoordinate(lat: 0, lon: 0),
                taskID: taskA,
                isClosed: false
            ),
            MissionPoint(
                pointId: "rally.2",
                label: "closerButClosed",
                kind: .rally,
                coordinate: RouteCoordinate(lat: 0.00001, lon: 0),
                taskID: taskA,
                isClosed: true
            ),
            MissionPoint(
                pointId: "rally.3",
                label: "otherTask",
                kind: .rally,
                coordinate: RouteCoordinate(lat: 0, lon: 0),
                taskID: taskB,
                isClosed: false
            ),
            MissionPoint(
                pointId: "rally.4",
                label: "missionWideFar",
                kind: .rally,
                coordinate: RouteCoordinate(lat: 2, lon: 2),
                taskID: nil,
                isClosed: false
            ),
        ]
        let best = try MissionRunMovePointParkPlanner.nearestPoint(
            kind: .rally,
            parentTaskID: taskA,
            among: points,
            vehicleLatDeg: 0,
            vehicleLonDeg: 0
        )
        XCTAssertEqual(best.pointId, "rally.1")
    }

    func test_buildParameters_includesExplicitPointKindAndLog() throws {
        let taskA = UUID()
        let points: [MissionPoint] = [
            MissionPoint(
                pointId: "extraction.1",
                label: "X",
                kind: .extraction,
                coordinate: RouteCoordinate(lat: 1, lon: 1),
                taskID: taskA,
                isClosed: false
            ),
        ]
        let params = try MissionRunMovePointParkPlanner.buildMovePointParkRecipeParameters(
            kind: .extraction,
            parentTaskID: taskA,
            missionPoints: points,
            vehicleLatitudeDeg: 1.00001,
            vehicleLongitudeDeg: 1.00001,
            currentRelativeAltitudeM: 3.5,
            yawDeg: 90
        )
        XCTAssertEqual(params.string(named: "procedureLogSummary"), "Move to extraction point [EP:1]")
        XCTAssertEqual(params.string(named: "pointKind"), "explicit")
        XCTAssertEqual(params.values["latitudeDeg"], .double(1))
        XCTAssertEqual(params.values["longitudeDeg"], .double(1))
        XCTAssertEqual(params.values["relativeAltitudeM"], .double(3.5))
        XCTAssertEqual(params.values["yawDeg"], .double(90))
    }

    func test_nearest_throwsWhenNoEligible() {
        let taskA = UUID()
        let points: [MissionPoint] = [
            MissionPoint(
                pointId: "rally.1",
                label: "closed",
                kind: .rally,
                coordinate: RouteCoordinate(lat: 0, lon: 0),
                taskID: taskA,
                isClosed: true
            ),
        ]
        XCTAssertThrowsError(
            try MissionRunMovePointParkPlanner.nearestPoint(
                kind: .rally,
                parentTaskID: taskA,
                among: points,
                vehicleLatDeg: 0,
                vehicleLonDeg: 0
            )
        ) { err in
            XCTAssertEqual(err as? MissionRunMovePointParkPlannerError, .noEligibleOpenPoint(kind: .rally))
        }
    }

    func test_buildParameters_throwsWithoutVehiclePosition() {
        let taskA = UUID()
        XCTAssertThrowsError(
            try MissionRunMovePointParkPlanner.buildMovePointParkRecipeParameters(
                kind: .rally,
                parentTaskID: taskA,
                missionPoints: [],
                vehicleLatitudeDeg: nil,
                vehicleLongitudeDeg: 1,
                currentRelativeAltitudeM: 0
            )
        ) { err in
            XCTAssertEqual(err as? MissionRunMovePointParkPlannerError, .noVehiclePosition)
        }
    }
}
