import XCTest
@testable import GuardianCore

final class GuardianSitlPortReleaseSettleTests: XCTestCase {
    func test_portReleaseSettleTimeout_defaults_to_two_point_five() {
        XCTAssertEqual(GuardianSitlPortReleaseSettle.portReleaseSettleTimeout(), 2.5, accuracy: 0.001)
    }

    func test_bulkSpawnInterSpawnPauseNanoseconds_defaults_to_150ms() {
        XCTAssertEqual(
            GuardianSitlPortReleaseSettle.bulkSpawnInterSpawnPauseNanoseconds(),
            150_000_000
        )
    }

    @MainActor
    func test_waitForRecentlyReleasedPortsToSettle_clears_after_stop() async {
        let sitl = SitlService()
        let id = UUID()
        sitl.seedMissionRunTestSitlRunningInstance(
            id: id,
            stackInstanceIndex: 0,
            mavlinkIngressPort: 42_001,
            mavlinkSystemID: 7
        )
        sitl.stop(id: id)
        await sitl.waitForRecentlyReleasedPortsToSettle(timeout: 0.05)
        // Second wait is a no-op when nothing is tracked.
        await sitl.waitForRecentlyReleasedPortsToSettle(timeout: 0.05)
    }
}
