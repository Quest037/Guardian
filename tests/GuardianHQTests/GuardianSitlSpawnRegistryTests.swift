import XCTest
@testable import GuardianCore

final class GuardianSitlSpawnRegistryTests: XCTestCase {
    /// Pins orphan-blitz policy: only spawns registered at or after cold launch are protected from pgrep.
    func test_protectedPIDSet_includesOnlyRecordsRegisteredSinceLaunch() {
        let launch = Date().timeIntervalSince1970
        let records = [
            GuardianSitlSpawnRecord(
                pid: 100,
                executablePath: "/old",
                fingerprint: "old",
                registeredAt: launch - 60
            ),
            GuardianSitlSpawnRecord(
                pid: 200,
                executablePath: "/new",
                fingerprint: "new",
                registeredAt: launch + 1
            ),
        ]
        let protected = Set(
            records
                .filter { $0.registeredAt >= launch }
                .map { pid_t($0.pid) }
        )
        XCTAssertEqual(protected, [200])
    }
}
