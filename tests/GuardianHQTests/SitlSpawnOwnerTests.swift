import XCTest
@testable import GuardianHQ

final class SitlSpawnOwnerTests: XCTestCase {
    func test_aliveInstances_filtersByOwnerAndAlive() {
        let trainingID = UUID()
        let formationID = UUID()
        let rows: [SitlRunningInstance] = [
            makeInstance(id: trainingID, owner: .trainingVehicle, alive: true),
            makeInstance(id: formationID, owner: .formationsPlayground, alive: true),
            makeInstance(id: UUID(), owner: .trainingVehicle, alive: false),
            makeInstance(id: UUID(), owner: .vehicles, alive: true),
        ]

        XCTAssertEqual(rows.aliveInstances(owner: .trainingVehicle).map(\.id), [trainingID])
        XCTAssertEqual(rows.aliveInstances(owner: .formationsPlayground).map(\.id), [formationID])
        XCTAssertEqual(rows.aliveInstances(owner: .vehicles).count, 1)
    }

    private func makeInstance(id: UUID, owner: SitlSpawnOwner, alive: Bool) -> SitlRunningInstance {
        SitlRunningInstance(
            id: id,
            platform: .px4,
            preset: .ugvWheeled,
            stackInstanceIndex: 0,
            mavlinkIngressPort: 14540,
            mavlinkSystemID: 1,
            px4GcsUdpPort: 18570,
            isAlive: alive,
            lastExitCode: nil,
            spawnOwner: owner
        )
    }
}
