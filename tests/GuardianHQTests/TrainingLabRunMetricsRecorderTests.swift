import XCTest
@testable import GuardianCore

@MainActor
final class TrainingLabRunMetricsRecorderTests: XCTestCase {
    func test_makeSnapshot_captures_path_source_and_along_track() {
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
                centerXM: 10,
                centerYM: 20,
                headingDeg: 90,
                widthM: 2,
                lengthM: 3,
                colorHex: "#f59e0b"
            ),
            requiresStrictEndSlotBox: false
        )
        let path: [RouteCoordinate] = [
            RouteCoordinate(lat: -35, lon: 149),
            RouteCoordinate(lat: -35.0005, lon: 149.0005),
        ]
        let track = TrainingLabRunSafetyMonitor.VehicleProgressTrack(
            bestAlongTrackM: 12.5,
            stagnantSince: nil
        )
        let finished = Date()
        let snapshot = TrainingLabRunMetricsRecorder.makeSnapshot(
            result: TrainingRunResult(
                phase: .failed,
                squadOutcomes: [
                    .failed(squadID: plan.squadID, code: .executionFailed, message: "stuck")
                ],
                startedAt: finished.addingTimeInterval(-60),
                finishedAt: finished
            ),
            statusMessage: "stuck",
            plans: [plan],
            squadOutcomes: [.failed(squadID: plan.squadID, code: .executionFailed, message: "stuck")],
            squadDriveFailed: [],
            transitPathsByVehicleID: [plan.vehicleID: path],
            pathSourceByVehicleID: [plan.vehicleID: .geodesicFallback],
            safetyProgressTracks: [plan.vehicleID: track],
            fleetLink: nil,
            startedAt: finished.addingTimeInterval(-60),
            finishedAt: finished,
            learningSquadID: plan.squadID
        )

        XCTAssertEqual(snapshot.vehicles.count, 1)
        XCTAssertEqual(snapshot.vehicles[0].pathSource, .geodesicFallback)
        XCTAssertEqual(snapshot.vehicles[0].pathPointCount, 2)
        XCTAssertEqual(snapshot.vehicles[0].bestAlongTrackM, 12.5)
        XCTAssertEqual(snapshot.result.phase, .failed)
        XCTAssertEqual(snapshot.learningSquadID, plan.squadID)
    }

    func test_record_emits_metrics_lines() {
        var lines: [String] = []
        let snapshot = TrainingLabRunCompletionSnapshot(
            result: .idle,
            statusMessage: "done",
            episodeDurationS: 42,
            learningSquadID: nil,
            vehicles: []
        )
        TrainingLabRunMetricsRecorder.record(snapshot) { lines.append($0) }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("[Metrics]"))
        XCTAssertTrue(lines[0].contains("42"))
    }
}
