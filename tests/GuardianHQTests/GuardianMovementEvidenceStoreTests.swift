import XCTest
@testable import GuardianHQ

@MainActor
final class GuardianMovementEvidenceStoreTests: XCTestCase {

    func test_appendAndLoad_jsonlRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("evidence.jsonl")
        let context = GuardianMovementSlotApproachContext(
            vehicleType: .ugvWheeled,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: 10,
            slot: RouteCoordinate(lat: -35.01, lon: 149),
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: 3,
            signedLateralErrorM: 0.5,
            distToSlotM: 4,
            primarySpeedMS: 1
        )
        let (plan, declined) = GuardianMovementPlanner.planSlotApproach(context)
        let record = GuardianMovementEvidenceRecord(
            vehicleType: .ugvWheeled,
            plan: plan,
            context: context,
            declinedMovementIDs: declined
        )
        try GuardianMovementEvidenceStore.append(record, fileURL: file)
        let loaded = try GuardianMovementEvidenceStore.loadAll(fileURL: file)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].selectedMovementID, plan.movementID)
    }
}
