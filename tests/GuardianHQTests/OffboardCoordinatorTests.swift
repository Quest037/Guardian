import XCTest

@testable import GuardianCore

final class OffboardCoordinatorTests: XCTestCase {

    func test_px4ParkBrakeLoopTickMessage_formats_speed_stable_ticks_and_iteration() {
        let line = OffboardCoordinator.px4ParkBrakeLoopTickMessage(
            iteration: 7,
            horizontalSpeedMS: 1.234,
            stableTicks: 2
        )
        XCTAssertTrue(line.contains("tick #7"))
        XCTAssertTrue(line.contains("horizontal|v|=1.23 m/s"))
        XCTAssertTrue(line.contains("stableTicks=2/6"))
    }

    func test_px4ParkBrakeLoopTickMessage_nil_speed_placeholder() {
        let line = OffboardCoordinator.px4ParkBrakeLoopTickMessage(
            iteration: 1,
            horizontalSpeedMS: nil,
            stableTicks: 0
        )
        XCTAssertTrue(line.contains("tick #1"))
        XCTAssertTrue(line.contains("horizontal|v|=nil m/s"))
    }

    func test_px4ParkPoseHold_carriesSnapshotYaw() {
        let hold = OffboardCoordinator.Px4ParkPoseHold(
            latitudeDeg: 50.753,
            longitudeDeg: -1.618,
            absoluteAltitudeM: 0,
            yawDeg: 127.5
        )
        XCTAssertEqual(hold.yawDeg, 127.5)
    }
}
