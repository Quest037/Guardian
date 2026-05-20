import XCTest
@testable import GuardianCore

final class TrainingSkillSearcherTests: XCTestCase {
    func test_candidates_reverseIntoSlot_respectsForbiddenForward() {
        let spawn = SimSpawnDefaults.default
        let layout = TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: spawn)
        let candidates = TrainingSkillSearcher.candidates(
            task: .reverseIntoSlot,
            layout: layout,
            vehicleType: .ugvWheeled,
            forbidden: [.driveForward],
            maxTrials: 50
        )
        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            for segment in candidate.segments where segment.bodyForwardMS > 0.02 {
                XCTFail("Forward segment should be excluded when forward is forbidden")
            }
        }
    }

    func test_candidates_producesLimitedTrialCount() {
        let layout = TrainingTaskLayoutFactory.layout(kind: .approachSlotForward, spawn: .default)
        let candidates = TrainingSkillSearcher.candidates(
            task: .approachSlotForward,
            layout: layout,
            vehicleType: .ugvWheeled,
            forbidden: [],
            maxTrials: 5
        )
        XCTAssertLessThanOrEqual(candidates.count, 5)
    }
}
