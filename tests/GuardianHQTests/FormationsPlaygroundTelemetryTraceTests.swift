import XCTest
@testable import GuardianHQ

final class FormationsPlaygroundTelemetryTraceTests: XCTestCase {

    private let slot = RouteCoordinate(lat: -35.0, lon: 149.0)
    private let slotID = UUID()

    private func hub(lat: Double, lon: Double, yaw: Double, course: Double? = nil) -> FleetHubVehicleTelemetry {
        var h = FleetHubVehicleTelemetry.empty
        h.latitudeDeg = lat
        h.longitudeDeg = lon
        h.yawDeg = yaw
        h.headingDeg = course ?? yaw
        return h
    }

    private func input(
        lat: Double,
        lon: Double,
        yaw: Double,
        movement: GuardianMovementID = .forwardPursuit,
        targetHeading: Double = 0
    ) -> FormationsPlaygroundTelemetryRecordInput {
        FormationsPlaygroundTelemetryRecordInput(
            slotID: slotID,
            vehicleLabel: "W1",
            vehicleID: "v1",
            hub: hub(lat: lat, lon: lon, yaw: yaw),
            slot: slot,
            targetHeadingDeg: targetHeading,
            primaryLatitudeDeg: -35.001,
            primaryLongitudeDeg: 149.0,
            primaryHeadingDeg: targetHeading,
            movementID: movement,
            bodyForwardMS: 1.0,
            yawspeedDegS: 10,
            streamPositionYawHold: false,
            arrivalM: 1.5,
            headingToleranceDeg: 5
        )
    }

    func test_sessionStart_recordedOnFirstSample() {
        var recorder = FormationsPlaygroundTelemetryTraceRecorder()
        recorder.beginSession(formationTitle: "Arrowhead", shapeTitle: "Tight", vehicleClassTitle: "UGV-W")
        recorder.record(input(lat: -35.0001, lon: 149.0001, yaw: 90))
        XCTAssertEqual(recorder.samples.filter { $0.kind == .sessionStart }.count, 1)
        XCTAssertEqual(recorder.samples.first?.vehicleLabel, "W1")
    }

    func test_change_dedupedUntilPositionMoves() {
        var recorder = FormationsPlaygroundTelemetryTraceRecorder()
        recorder.beginSession(formationTitle: "Convoy", shapeTitle: "Wide", vehicleClassTitle: "UAV-C")
        recorder.record(input(lat: -35.0001, lon: 149.0001, yaw: 90))
        let afterStart = recorder.samples.count
        recorder.record(input(lat: -35.0001, lon: 149.0001, yaw: 90))
        XCTAssertEqual(recorder.samples.count, afterStart)
        recorder.record(input(lat: -35.0008, lon: 149.0001, yaw: 90))
        XCTAssertGreaterThan(recorder.samples.count, afterStart)
    }

    func test_plainTextExport_includesOutcomeLine() {
        var recorder = FormationsPlaygroundTelemetryTraceRecorder()
        recorder.beginSession(formationTitle: "Chevron", shapeTitle: "Tight", vehicleClassTitle: "UGV-W")
        recorder.record(input(lat: -35.0, lon: 149.0, yaw: 2, targetHeading: 2))
        recorder.record(input(lat: -35.0, lon: 149.0, yaw: 2, targetHeading: 2))
        let text = recorder.plainTextExport()
        XCTAssertTrue(text.contains("# Guardian Formations telemetry trace"))
        XCTAssertTrue(text.contains("outcome:"))
    }

    func test_jsonLinesExport_includesSessionHeader() {
        var recorder = FormationsPlaygroundTelemetryTraceRecorder()
        recorder.beginSession(formationTitle: "Convoy", shapeTitle: "Tight", vehicleClassTitle: "UGV-T")
        recorder.record(input(lat: -35.0, lon: 149.0, yaw: 0))
        let jsonl = recorder.jsonLinesExport()
        XCTAssertTrue(jsonl.contains("\"type\":\"session\""))
        XCTAssertTrue(jsonl.contains("\"event\":\"sessionStart\""))
    }
}
