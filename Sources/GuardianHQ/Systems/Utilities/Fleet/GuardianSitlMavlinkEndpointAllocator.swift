import Foundation

/// Reserves MAVLink UDP ingress ports and system IDs for built-in SITL so wipe → respawn does not
/// reuse the same localhost endpoints and `sysid:n` keys as the previous session.
enum GuardianSitlMavlinkEndpointAllocator {
    /// UDP ports reserved for Guardian SITL MAVSDK ingress (`udpin://0.0.0.0:port`).
    static let ingressPortRange: ClosedRange<Int> = 42_000...42_999

    static let systemIDRange: ClosedRange<Int> = 1...254

    /// Next bindable UDP port in ``ingressPortRange``, excluding ports already assigned to live instances.
    static func reserveMavlinkIngressPort(occupied: Set<Int>) -> Int? {
        let band = Array(ingressPortRange)
        guard !band.isEmpty else { return nil }
        let start = Int.random(in: 0..<band.count)
        for offset in 0..<band.count {
            let port = band[(start + offset) % band.count]
            if occupied.contains(port) { continue }
            if GuardianUdpPortUtilities.isUdpPortBindable(port) { return port }
        }
        return nil
    }

    /// Next free MAVLink system id in ``systemIDRange``, excluding ids already in use by live instances.
    static func reserveMavlinkSystemID(occupied: Set<Int>) -> Int? {
        var candidates = systemIDRange.filter { !occupied.contains($0) }
        guard !candidates.isEmpty else { return nil }
        candidates.shuffle()
        return candidates.first
    }
}
