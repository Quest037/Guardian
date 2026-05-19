import XCTest

@testable import GuardianHQ

final class TrainingLabLearningSquadTests: XCTestCase {
    func test_clamp_defaults_to_alpha_when_unset() {
        let alpha = UUID()
        let beta = UUID()
        let squads = [
            TrainingLabSquad(id: alpha, primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled)),
            TrainingLabSquad(id: beta, primary: TrainingLabRosterEntry(vehicleClass: .ugvTracked)),
        ]
        XCTAssertEqual(
            TrainingLabLearningSquadSelection.clampedLearningSquadID(current: nil, squads: squads),
            alpha
        )
    }

    func test_clamp_after_removed_squad_falls_back_to_alpha() {
        let alpha = UUID()
        let beta = UUID()
        let squads = [TrainingLabSquad(id: alpha, primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled))]
        XCTAssertEqual(
            TrainingLabLearningSquadSelection.clampedLearningSquadID(current: beta, squads: squads),
            alpha
        )
    }

    func test_single_vehicle_squad_is_still_a_squad_for_formation_gate() {
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            wingmen: [TrainingLabRosterEntry(vehicleClass: .ugvWheeled)]
        )
        XCTAssertFalse(squad.isSingleVehicle)
        XCTAssertEqual(squad.vehicleCount, 2)

        var solo = squad
        solo.wingmen = []
        XCTAssertTrue(solo.isSingleVehicle)
        XCTAssertEqual(solo.vehicleCount, 1)
    }

    func test_persist_round_trips_learning_squad_and_task_kind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("roster.json")

        let beta = UUID()
        let squads = [
            TrainingLabSquad(
                primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                taskKind: .approachSlotForward
            ),
            TrainingLabSquad(
                id: beta,
                primary: TrainingLabRosterEntry(vehicleClass: .ugvTracked),
                taskKind: .alignHeadingAtSlot
            ),
        ]

        let snapshot = TrainingLabRosterStore.snapshot(from: squads, learningSquadID: beta)
        try TrainingLabRosterStore.save(snapshot, fileURL: file)

        let loaded = try TrainingLabRosterStore.load(fileURL: file)
        XCTAssertEqual(loaded.learningSquadID, beta)
        let restored = TrainingLabRosterStore.squads(from: loaded)
        XCTAssertEqual(restored[0].taskKind, .approachSlotForward)
        XCTAssertEqual(restored[1].taskKind, .alignHeadingAtSlot)
    }
}
