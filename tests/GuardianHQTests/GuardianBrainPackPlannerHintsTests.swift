import XCTest

@testable import GuardianHQ

final class GuardianBrainPackPlannerHintsTests: XCTestCase {
    func test_plannerHints_nav2_includes_overlay_json() {
        let layout = TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default)
        let hints = GuardianBrainPackBuilder.plannerHints(
            from: GuardianBrainPackTrainingPlannerContext(
                vehicleClass: .ugvWheeled,
                layout: layout,
                segments: [.forward(0.6, durationS: 2)],
                planPathSource: .nav2,
                nav2StackReady: true,
                nav2StackStatus: "ready",
                gazeboEnvironmentId: "bundled.open_field",
                planWaypointCount: 12
            )
        )
        XCTAssertEqual(hints?.frameId, "map")
        XCTAssertEqual(hints?.maxSpeedMS, 0.6)
        XCTAssertNotNil(hints?.nav2ParamOverlayJSON)
        XCTAssertTrue(hints?.nav2ParamOverlayJSON?.contains("nav2") == true)
        XCTAssertNil(hints?.aerostack2ParamOverlayJSON)
    }

    func test_plannerHints_aerostack2_for_uav() {
        let layout = TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default)
        let hints = GuardianBrainPackBuilder.plannerHints(
            from: GuardianBrainPackTrainingPlannerContext(
                vehicleClass: .uavCopter,
                layout: layout,
                segments: [.forward(1.2, durationS: 1)],
                planPathSource: .unavailable,
                nav2StackReady: false,
                nav2StackStatus: "inactive",
                gazeboEnvironmentId: nil,
                planWaypointCount: 0
            )
        )
        XCTAssertNotNil(hints?.aerostack2ParamOverlayJSON)
        XCTAssertNil(hints?.nav2ParamOverlayJSON)
    }

    func test_makePack_retains_planner_hints() throws {
        let skill = TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.forward(0.5, durationS: 1)],
            score: TrainingSkillScore(
                positionErrorM: 0.2,
                headingErrorDeg: 1,
                episodeDurationS: 5,
                constraintViolations: [],
                succeeded: true
            ),
            layout: TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default),
            trialIndex: 0,
            summary: "test"
        )
        let hints = GuardianBrainPackPlannerHints(frameId: "map", maxSpeedMS: 0.5)
        let pack = try GuardianBrainPackBuilder.makePack(
            from: skill,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test",
            plannerHints: hints
        )
        XCTAssertEqual(pack.plannerHints, hints)
    }

    func test_inferredMaxSpeedMS_uses_segment_peak() {
        XCTAssertEqual(
            GuardianBrainPackBuilder.inferredMaxSpeedMS(from: [.forward(0.3, durationS: 1), .forward(0.8, durationS: 1)]),
            0.8
        )
    }
}
