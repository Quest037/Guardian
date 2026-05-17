import Darwin
import Foundation

enum GuardianUdpPortUtilities {
    /// Port from `udpin://host:port` (Guardian SITL MAVSDK ingress).
    static func udpInboundListenPort(from connectionURL: String) -> Int? {
        let trimmed = connectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("udpin://") else { return nil }
        guard let hostPort = trimmed.split(separator: "//", maxSplits: 1).last else { return nil }
        let portPart = hostPort.split(separator: ":").last.map(String.init) ?? ""
        guard let port = Int(portPart), port > 0, port < 65_536 else { return nil }
        return port
    }

    /// `true` when this process can bind the UDP port now (best-effort; same probe as ``SitlService`` PX4 slot pick).
    static func isUdpPortBindable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
    }

    /// Poll until the inbound MAVLink UDP port is free or ``timeout`` elapses.
    static func waitForUdpInboundPortBindable(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isUdpPortBindable(port) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return isUdpPortBindable(port)
    }
}
