import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunSquadWingmanFollowPhaseTests: XCTestCase {
    func test_operatorLabel_convoyFollowing() {
        XCTAssertEqual(
            MissionRunSquadWingmanFollowPhase.following.operatorStatusLabel,
            "Following convoy"
        )
    }

    func test_operatorLabel_streamFailed() {
        XCTAssertEqual(
            MissionRunSquadWingmanFollowPhase.streamFailed.operatorStatusLabel,
            "Formation follow unavailable"
        )
    }

    func test_operatorLabel_idle_nil() {
        XCTAssertNil(MissionRunSquadWingmanFollowPhase.idle.operatorStatusLabel)
    }

    func test_operatorLabel_assemblingConvoy() {
        XCTAssertEqual(
            MissionRunSquadWingmanFollowPhase.assemblingConvoy.operatorStatusLabel,
            "Forming convoy"
        )
    }

    func test_operatorLabel_approachingRoute() {
        XCTAssertEqual(
            MissionRunSquadWingmanFollowPhase.approachingRoute.operatorStatusLabel,
            "Approaching route"
        )
    }

    func test_operatorLabel_holdingBetweenCycles() {
        XCTAssertEqual(
            MissionRunSquadWingmanFollowPhase.holdingBetweenCycles.operatorStatusLabel,
            "Holding position"
        )
    }

    func test_streamReconnectPolicy_lockedAttempts() {
        XCTAssertEqual(MissionSquadConvoyFollowControlPolicy.streamReconnectMaxAttempts, 5)
        XCTAssertEqual(MissionSquadConvoyFollowControlPolicy.streamReconnectCooldownS, 1.0)
    }
}
