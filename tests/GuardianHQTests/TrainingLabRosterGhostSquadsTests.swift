import XCTest

@testable import GuardianCore

@MainActor
final class TrainingLabRosterGhostSquadsTests: XCTestCase {
    func test_snapshot_omits_squads_without_linked_simulator() {
        let linkedID = UUID()
        let linkedSlot = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-ugv-1",
            linkReady: true,
            preflightPassed: true
        )
        var linkedPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        linkedPrimary.slotState = linkedSlot

        let squads = [
            TrainingLabSquad(primary: TrainingLabRosterEntry(vehicleClass: .ugvTracked)),
            TrainingLabSquad(id: linkedID, primary: linkedPrimary),
        ]

        let snapshot = TrainingLabRosterStore.snapshot(from: squads, learningSquadID: squads[0].id)

        XCTAssertEqual(snapshot.squads.count, 1)
        XCTAssertEqual(snapshot.squads[0].id, linkedID)
        XCTAssertEqual(snapshot.squads[0].primary.vehicleID, "training-ugv-1")
        XCTAssertEqual(snapshot.learningSquadID, linkedID)
    }

    func test_squads_from_snapshot_without_vehicle_ids_is_empty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("roster.json")

        let snapshot = TrainingLabRosterStore.Snapshot(
            squads: [
                TrainingLabRosterStore.PersistedSquad(
                    id: UUID(),
                    primary: TrainingLabRosterStore.PersistedEntry(
                        vehicleClass: .ugvWheeled,
                        vehicleSizeTier: .medium,
                        vehicleID: nil
                    ),
                    wingmen: [],
                    formationPolicy: .default
                ),
            ]
        )
        try TrainingLabRosterStore.save(snapshot, fileURL: file)

        let loaded = try TrainingLabRosterStore.load(fileURL: file)
        let restored = TrainingLabRosterStore.squads(from: loaded)

        XCTAssertTrue(restored.isEmpty)
    }
}
