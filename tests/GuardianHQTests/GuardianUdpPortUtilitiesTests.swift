import XCTest
@testable import GuardianHQ

final class GuardianUdpPortUtilitiesTests: XCTestCase {
    func test_udpInboundListenPort_parses_standard_sitl_ingress() {
        XCTAssertEqual(
            GuardianUdpPortUtilities.udpInboundListenPort(from: "udpin://0.0.0.0:14560"),
            14_560
        )
    }
}
