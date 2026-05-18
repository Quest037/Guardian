import XCTest
@testable import GuardianHQ

@MainActor
final class TrainingSkillStoreTests: XCTestCase {
    func test_appendPromoted_replacesSameTaskAndClass() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("training_skills_\(UUID().uuidString).json")
        let layout = TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default)
        let score = TrainingSkillScore(
            positionErrorM: 1,
            headingErrorDeg: 2,
            episodeDurationS: 10,
            constraintViolations: [],
            succeeded: true
        )
        let first = TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.hold(durationS: 1)],
            score: score,
            layout: layout,
            trialIndex: 0,
            summary: "first"
        )
        let second = TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.hold(durationS: 2)],
            score: score,
            layout: layout,
            trialIndex: 1,
            summary: "second"
        )
        try TrainingSkillStore.appendPromoted(first, fileURL: url)
        try TrainingSkillStore.appendPromoted(second, fileURL: url)
        let all = try TrainingSkillStore.loadAll(fileURL: url)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].summary, "second")
        try? FileManager.default.removeItem(at: url)
    }
}
