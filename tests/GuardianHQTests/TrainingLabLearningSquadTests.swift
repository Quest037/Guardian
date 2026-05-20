import XCTest

@testable import GuardianCore

final class TrainingLabLearningSquadTests: XCTestCase {
    func test_clamp_defaults_to_alpha_when_unset() {
        let alpha = UUID()
        let beta = UUID()
        var alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        alphaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "a",
            linkReady: true
        )
        var betaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvTracked)
        betaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "b",
            linkReady: true
        )
        let squads = [
            TrainingLabSquad(id: alpha, primary: alphaPrimary),
            TrainingLabSquad(id: beta, primary: betaPrimary),
        ]
        XCTAssertEqual(
            TrainingLabLearningSquadSelection.clampedLearningSquadID(current: nil, squads: squads),
            alpha
        )
    }

    func test_clamp_skips_unlinked_squads() {
        let ghost = UUID()
        let alpha = UUID()
        var alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        alphaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "linked",
            linkReady: true
        )
        let squads = [
            TrainingLabSquad(id: ghost, primary: TrainingLabRosterEntry(vehicleClass: .ugvTracked)),
            TrainingLabSquad(id: alpha, primary: alphaPrimary),
        ]
        XCTAssertEqual(
            TrainingLabLearningSquadSelection.clampedLearningSquadID(current: ghost, squads: squads),
            alpha
        )
    }

    func test_clamp_after_removed_squad_falls_back_to_alpha() {
        let alpha = UUID()
        let beta = UUID()
        var alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        alphaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "a",
            linkReady: true
        )
        let squads = [TrainingLabSquad(id: alpha, primary: alphaPrimary)]
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
        var alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        alphaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-alpha",
            linkReady: true,
            preflightPassed: true
        )
        var betaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvTracked)
        betaPrimary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-beta",
            linkReady: true,
            preflightPassed: true
        )
        let squads = [
            TrainingLabSquad(
                primary: alphaPrimary,
                taskKind: .approachSlotForward
            ),
            TrainingLabSquad(
                id: beta,
                primary: betaPrimary,
                taskKind: .alignHeadingAtSlot
            ),
        ]

        let snapshot = TrainingLabRosterStore.snapshot(from: squads, learningSquadID: beta)
        try TrainingLabRosterStore.save(snapshot, fileURL: file)

        let loaded = try TrainingLabRosterStore.load(fileURL: file)
        XCTAssertEqual(loaded.learningSquadID, beta)
        let restored = TrainingLabRosterStore.squads(from: loaded)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].taskKind, .approachSlotForward)
        XCTAssertEqual(restored[0].primary.restoredLinkVehicleID, "training-alpha")
        XCTAssertEqual(restored[1].taskKind, .alignHeadingAtSlot)
        XCTAssertEqual(restored[1].primary.restoredLinkVehicleID, "training-beta")
    }
}
