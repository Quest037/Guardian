import XCTest

@testable import GuardianCore

final class TrainingLabTransitMotionProofTests: XCTestCase {
    func test_movementSummary_reports_distance_when_fixes_present() {
        let start = TrainingLabTransitMotionProof.Snapshot(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            isArmed: true,
            hasFix: true
        )
        let end = TrainingLabTransitMotionProof.Snapshot(
            latitudeDeg: -35.0001,
            longitudeDeg: 149.0001,
            headingDeg: 45,
            isArmed: true,
            hasFix: true
        )
        let summary = TrainingLabTransitMotionProof.movementSummary(start: start, end: end)
        XCTAssertTrue(summary.contains("moved"))
        XCTAssertFalse(summary.contains("below"))
    }

    func test_movementSummary_flags_insufficient_motion() {
        let start = TrainingLabTransitMotionProof.Snapshot(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            isArmed: true,
            hasFix: true
        )
        let end = TrainingLabTransitMotionProof.Snapshot(
            latitudeDeg: -35.000001,
            longitudeDeg: 149.000001,
            headingDeg: 0,
            isArmed: true,
            hasFix: true
        )
        let summary = TrainingLabTransitMotionProof.movementSummary(start: start, end: end)
        XCTAssertTrue(summary.contains("below"))
    }
}
