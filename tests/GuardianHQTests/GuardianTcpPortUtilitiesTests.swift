import Darwin
import XCTest
@testable import GuardianHQ

final class GuardianTcpPortUtilitiesTests: XCTestCase {
    func test_isTcpPortBindable_falseWhenPortInUse() throws {
        let (port, fd) = try reserveListeningSocket()
        defer { close(fd) }
        XCTAssertFalse(GuardianTcpPortUtilities.isTcpPortBindable(port))
    }

    func test_isTcpPortListening_trueWhenPortHasListener() throws {
        let (port, fd) = try reserveListeningSocket()
        defer { close(fd) }
        XCTAssertTrue(GuardianTcpPortUtilities.isTcpPortListening(port: port))
    }

    private func reserveListeningSocket() throws -> (port: Int, fd: Int32) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "GuardianTcpPortUtilitiesTests", code: 1)
        }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
        guard bound, listen(fd, 1) == 0 else {
            close(fd)
            throw NSError(domain: "GuardianTcpPortUtilitiesTests", code: 2)
        }
        var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        var out = sockaddr_in()
        guard getsockname(fd, withUnsafeMutablePointer(to: &out) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }, &len) == 0 else {
            close(fd)
            throw NSError(domain: "GuardianTcpPortUtilitiesTests", code: 3)
        }
        let port = Int(UInt16(bigEndian: out.sin_port))
        return (port, fd)
    }
}
