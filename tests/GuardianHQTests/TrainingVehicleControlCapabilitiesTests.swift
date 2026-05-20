import XCTest
@testable import GuardianCore

final class TrainingVehicleControlCapabilitiesTests: XCTestCase {
    func test_ugv_supportsDiscreteDriveAndTurnAxes() {
        let axes = TrainingVehicleControlCapabilities.supportedAxes(vehicleType: .ugvWheeled)
        XCTAssertTrue(axes.contains(.driveForward))
        XCTAssertTrue(axes.contains(.driveReverse))
        XCTAssertTrue(axes.contains(.turnClockwise))
        XCTAssertTrue(axes.contains(.turnCounterClockwise))
        XCTAssertFalse(axes.contains(.strafeRight))
        XCTAssertFalse(axes.contains(.climb))
    }

    func test_forbiddenForward_blocksPositiveForwardSegment() {
        let segment = TrainingControlSegment.forward(0.5, durationS: 2)
        let violations = TrainingVehicleControlCapabilities.validateSegment(
            segment,
            vehicleType: .ugvWheeled,
            forbidden: [.driveForward]
        )
        XCTAssertTrue(violations.contains(.driveForward))
    }

    func test_reverseAllowedWhenForwardForbidden() {
        let segment = TrainingControlSegment.reverse(0.4, durationS: 3)
        let violations = TrainingVehicleControlCapabilities.validateSegment(
            segment,
            vehicleType: .ugvWheeled,
            forbidden: [.driveForward]
        )
        XCTAssertTrue(violations.isEmpty)
    }

    func test_forbiddenReverse_blocksReverseSegment() {
        let segment = TrainingControlSegment.reverse(0.4, durationS: 3)
        let violations = TrainingVehicleControlCapabilities.validateSegment(
            segment,
            vehicleType: .ugvWheeled,
            forbidden: [.driveReverse]
        )
        XCTAssertTrue(violations.contains(.driveReverse))
    }

    func test_forbiddenClockwise_blocksPositiveYaw() {
        let segment = TrainingControlSegment.yaw(20, durationS: 2)
        let violations = TrainingVehicleControlCapabilities.validateSegment(
            segment,
            vehicleType: .ugvWheeled,
            forbidden: [.turnClockwise]
        )
        XCTAssertTrue(violations.contains(.turnClockwise))
    }
}
