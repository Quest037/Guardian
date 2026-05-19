import XCTest

@testable import GuardianHQ

final class TrainingLabRosterStoreTests: XCTestCase {
    func test_roundTrip_squads_and_formation_policy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("roster.json")

        let squads = [
            TrainingLabSquad(
                primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled, vehicleSizeTier: .medium),
                wingmen: [TrainingLabRosterEntry(vehicleClass: .ugvWheeled, vehicleSizeTier: .small)],
                formationPolicy: TrainingLabSquadFormationPolicy(
                    startFormation: .chevron,
                    startSpacing: .loose,
                    endFormation: .convoy,
                    endSpacing: .tight
                )
            ),
        ]

        let snapshot = TrainingLabRosterStore.snapshot(from: squads, learningSquadID: squads[0].id)
        try TrainingLabRosterStore.save(snapshot, fileURL: file)

        let loaded = try TrainingLabRosterStore.load(fileURL: file)
        let restored = TrainingLabRosterStore.squads(from: loaded)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].formationPolicy.startFormation, .chevron)
        XCTAssertEqual(restored[0].formationPolicy.startSpacing, .loose)
        XCTAssertEqual(restored[0].formationPolicy.endFormation, .convoy)
        XCTAssertEqual(restored[0].formationPolicy.endSpacing, .tight)
        XCTAssertEqual(restored[0].wingmen.count, 1)
    }
}
