import XCTest

@testable import GuardianCore

final class MissionControlSetupSimDragOverlayPolicyTests: XCTestCase {
    func test_shouldClearByTimeout_false_early() {
        let started = Date()
        XCTAssertFalse(
            MissionControlSetupSimDragOverlayPolicy.shouldClearOverlayByTimeout(
                overlayStartedAt: started,
                now: started.addingTimeInterval(3)
            )
        )
    }

    func test_shouldClearByTimeout_true_after_window() {
        let started = Date()
        XCTAssertTrue(
            MissionControlSetupSimDragOverlayPolicy.shouldClearOverlayByTimeout(
                overlayStartedAt: started,
                now: started.addingTimeInterval(10.01)
            )
        )
    }

    func test_hubMatches_within_epsilon() {
        let pending = RouteCoordinate(lat: 10, lon: 20)
        let hub = RouteCoordinate(
            lat: pending.lat + MissionControlSetupSimDragOverlayPolicy.hubMatchEpsilonDegrees * 0.5,
            lon: pending.lon
        )
        XCTAssertTrue(MissionControlSetupSimDragOverlayPolicy.hubMatches(pendingCoordinate: pending, hubCoordinate: hub))
    }

    func test_hubMatches_false_when_far() {
        let pending = RouteCoordinate(lat: 10, lon: 20)
        let hub = RouteCoordinate(lat: pending.lat + 0.01, lon: pending.lon)
        XCTAssertFalse(MissionControlSetupSimDragOverlayPolicy.hubMatches(pendingCoordinate: pending, hubCoordinate: hub))
    }

    func test_updatedHubAgreesSince_starts_streak_on_first_match() {
        let t0 = Date()
        let since = MissionControlSetupSimDragOverlayPolicy.updatedHubAgreesSince(
            hubMatchesPending: true,
            previous: nil,
            now: t0
        )
        XCTAssertEqual(since, t0)
    }

    func test_updatedHubAgreesSince_preserves_anchor() {
        let t0 = Date().addingTimeInterval(-2)
        let now = Date()
        let since = MissionControlSetupSimDragOverlayPolicy.updatedHubAgreesSince(
            hubMatchesPending: true,
            previous: t0,
            now: now
        )
        XCTAssertEqual(since, t0)
    }

    func test_updatedHubAgreesSince_clears_on_mismatch() {
        let t0 = Date()
        XCTAssertNil(
            MissionControlSetupSimDragOverlayPolicy.updatedHubAgreesSince(
                hubMatchesPending: false,
                previous: t0,
                now: Date()
            )
        )
    }

    func test_isSustainedHubAgreement_false_until_hold() {
        let t0 = Date()
        XCTAssertFalse(
            MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(
                hubAgreesSince: t0,
                now: t0.addingTimeInterval(MissionControlSetupSimDragOverlayPolicy.hubAgreesSustainSeconds * 0.5)
            )
        )
    }

    func test_isSustainedHubAgreement_true_after_hold() {
        let t0 = Date()
        XCTAssertTrue(
            MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(
                hubAgreesSince: t0,
                now: t0.addingTimeInterval(MissionControlSetupSimDragOverlayPolicy.hubAgreesSustainSeconds + 0.05)
            )
        )
    }

    func test_isSustainedHubAgreement_false_when_nil() {
        XCTAssertFalse(
            MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(hubAgreesSince: nil, now: Date())
        )
    }
}
