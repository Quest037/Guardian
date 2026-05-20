import XCTest
@testable import GuardianCore

final class GuardianSitlMavlinkEndpointAllocatorTests: XCTestCase {
    func test_ingressPortRange_is_documented_guardian_band() {
        XCTAssertEqual(GuardianSitlMavlinkEndpointAllocator.ingressPortRange, 42_000...42_999)
    }

    func test_systemIDRange_excludes_broadcast() {
        XCTAssertEqual(GuardianSitlMavlinkEndpointAllocator.systemIDRange, 1...254)
    }

    func test_reserveMavlinkSystemID_skips_occupied() {
        let reserved = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkSystemID(occupied: [1, 2, 3])
        XCTAssertNotNil(reserved)
        XCTAssertFalse([1, 2, 3].contains(reserved!))
        XCTAssertTrue(GuardianSitlMavlinkEndpointAllocator.systemIDRange.contains(reserved!))
        XCTAssertNil(
            GuardianSitlMavlinkEndpointAllocator.reserveMavlinkSystemID(
                occupied: Set(GuardianSitlMavlinkEndpointAllocator.systemIDRange)
            )
        )
    }

    func test_reserveMavlinkIngressPort_respects_band_and_occupied() {
        guard let port = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: []) else {
            XCTFail("Expected a bindable port in the Guardian band")
            return
        }
        XCTAssertTrue(GuardianSitlMavlinkEndpointAllocator.ingressPortRange.contains(port))
        XCTAssertNil(
            GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: [port])
        )
    }

    func test_reserveMavlinkIngressPort_returns_nil_when_band_fully_occupied() {
        let occupied = Set(GuardianSitlMavlinkEndpointAllocator.ingressPortRange)
        XCTAssertNil(GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: occupied))
    }
}
