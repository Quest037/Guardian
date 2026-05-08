import Foundation
import Network

/// Tiny raw-MAVLink sender for the one operation MAVSDK doesn't expose: changing
/// the autopilot's flight mode. Used by the LiveDrive PX4-ground keyboard path.
///
/// ## Why this exists (and why `Shell.send("commander mode manual")` doesn't work)
///
/// MAVSDK's `Shell` plugin transports text via MAVLink `SERIAL_CONTROL` messages
/// addressed to the `MAVLINK_SHELL` device. PX4 only routes those bytes onward
/// when a `mavlink_shell` instance is running on the receiving link — and PX4
/// SITL **does not** auto-start a `mavlink_shell` on the Onboard link that
/// `mavsdk_server` connects through (see `src/modules/mavlink/mavlink_main.cpp`,
/// `Mavlink::start_shell()` is on-demand and the shell process must already be
/// scheduled by `nsh` for output to flow). The result: `Shell.send` "succeeds"
/// at the gRPC layer (mavsdk_server delivered the message) and PX4 silently
/// drops it. The rover stays in HOLD even though we asked for MANUAL.
///
/// ## What this does instead
///
/// Builds a MAVLink v2 `SET_MODE` (msg-id 11) packet and posts it to PX4's
/// "Normal" MAVLink instance over UDP — the same path QGroundControl uses for
/// flight-mode buttons. PX4's commander handles `SET_MODE` via the standard
/// command pipeline and emits a `COMMAND_ACK` plus a `vehicle_status` update,
/// so the mode change actually sticks and shows up on `Telemetry.flightMode`.
///
/// ## PX4 custom-mode encoding
///
/// PX4 packs the flight mode into the 32-bit `custom_mode` field of `SET_MODE`:
///   `bits  0-15` reserved (0)
///   `bits 16-23` main mode (e.g. `1` = MANUAL, `3` = POSCTL, `6` = OFFBOARD)
///   `bits 24-31` sub-mode  (only used when main = AUTO)
/// `base_mode` must include `MAV_MODE_FLAG_CUSTOM_MODE_ENABLED` (bit 0) so the
/// commander reads `custom_mode` rather than the legacy bit-flag scheme.
///
/// ## Port selection
///
/// PX4 SITL listens on its "GCS" MAVLink instance at UDP `18570 + instance`
/// (see `Px4SitlLocator.px4SihGcsUdpPort`). We send the SET_MODE there because
/// (a) the port is stable across PX4 versions, (b) the GCS link is always
/// running with the standard command set, and (c) sharing the Onboard port
/// with `mavsdk_server` invites packet collisions on the local socket.
enum Px4ModeCommander {
    /// PX4 custom main-mode IDs (`PX4_CUSTOM_MAIN_MODE_*` in `commander/px4_custom_mode.h`).
    enum MainMode: UInt8 {
        case manual = 1
        case altctl = 2
        case posctl = 3
        case auto = 4
        case acro = 5
        case offboard = 6
        case stabilized = 7
        case rattitude = 8
        case simple = 9
    }

    /// Fire-and-forget. We don't wait for `COMMAND_ACK` — the caller (LiveDrive)
    /// observes `Telemetry.flightMode` and is happy as soon as PX4 reports the
    /// new mode. If the UDP send itself errors out (e.g. nothing listening on
    /// the target port), the `log` closure receives a single line.
    static func setMode(
        host: String = "127.0.0.1",
        port: UInt16,
        targetSystem: UInt8 = 1,
        mainMode: MainMode,
        subMode: UInt8 = 0,
        log: (@Sendable (String) -> Void)? = nil
    ) async {
        let customMode = (UInt32(mainMode.rawValue) << 16) | (UInt32(subMode) << 24)
        let packet = buildSetModePacket(targetSystem: targetSystem, customMode: customMode)
        await sendUDP(packet: packet, host: host, port: port, log: log)
    }

    // MARK: - MAVLink v2 packet builder

    /// Build a complete MAVLink v2 `SET_MODE` packet (header + payload + CRC).
    private static func buildSetModePacket(
        targetSystem: UInt8,
        customMode: UInt32
    ) -> Data {
        // SET_MODE payload — MAVLink reorders fields by size descending
        // (`custom_mode` 4 bytes first, then the two `uint8_t` fields).
        var payload = Data(capacity: 6)
        payload.append(UInt8(customMode & 0xFF))
        payload.append(UInt8((customMode >> 8) & 0xFF))
        payload.append(UInt8((customMode >> 16) & 0xFF))
        payload.append(UInt8((customMode >> 24) & 0xFF))
        payload.append(targetSystem)
        payload.append(0x01) // base_mode = MAV_MODE_FLAG_CUSTOM_MODE_ENABLED

        // SET_MODE crc_extra is 89 (computed once from the message definition;
        // see `MAVLINK_MESSAGE_CRC` table in any generated dialect header).
        return assemblePacketV2(
            messageId: 11,
            payload: payload,
            crcExtra: 89,
            systemId: 255, // Conventional GCS/operator system ID.
            componentId: 0,
            sequence: nextSequence()
        )
    }

    /// Wrap a MAVLink v2 frame around `payload`. No payload truncation: writing
    /// the 6 bytes literally is well within the spec and avoids subtle length
    /// mismatches with strict receivers.
    private static func assemblePacketV2(
        messageId: UInt32,
        payload: Data,
        crcExtra: UInt8,
        systemId: UInt8,
        componentId: UInt8,
        sequence: UInt8
    ) -> Data {
        var packet = Data(capacity: 12 + payload.count)
        packet.append(0xFD)
        packet.append(UInt8(payload.count))
        packet.append(0) // incompat flags (no signing)
        packet.append(0) // compat flags
        packet.append(sequence)
        packet.append(systemId)
        packet.append(componentId)
        packet.append(UInt8(messageId & 0xFF))
        packet.append(UInt8((messageId >> 8) & 0xFF))
        packet.append(UInt8((messageId >> 16) & 0xFF))
        packet.append(payload)

        // CRC is computed across everything from `len` through the last payload
        // byte, plus the per-message `crc_extra`. Header magic byte is excluded.
        var crcInput = Data(capacity: 11 + payload.count)
        crcInput.append(UInt8(payload.count))
        crcInput.append(0)
        crcInput.append(0)
        crcInput.append(sequence)
        crcInput.append(systemId)
        crcInput.append(componentId)
        crcInput.append(UInt8(messageId & 0xFF))
        crcInput.append(UInt8((messageId >> 8) & 0xFF))
        crcInput.append(UInt8((messageId >> 16) & 0xFF))
        crcInput.append(payload)
        crcInput.append(crcExtra)

        let crc = x25Crc(crcInput)
        packet.append(UInt8(crc & 0xFF))
        packet.append(UInt8((crc >> 8) & 0xFF))
        return packet
    }

    /// Monotonically-increasing seq for the GCS sender pseudo-system. PX4
    /// doesn't enforce strict order on SET_MODE so wrap-around is harmless.
    /// `nonisolated(unsafe)` because access is gated by the adjacent `NSLock`,
    /// which Swift 6 strict-concurrency can't reason about on its own.
    private static let sequenceLock = NSLock()
    nonisolated(unsafe) private static var sequenceCounter: UInt8 = 0
    private static func nextSequence() -> UInt8 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        sequenceCounter = sequenceCounter &+ 1
        return sequenceCounter
    }

    /// MAVLink CRC = X.25 CRC-16 (init `0xFFFF`, polynomial `0x1021`,
    /// reflected). Matches the reference accumulator in `mavlink_helpers.h`.
    private static func x25Crc(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            var tmp = UInt16(byte) ^ (crc & 0x00FF)
            tmp ^= (tmp << 4) & 0x00FF
            let high = (crc >> 8) & 0x00FF
            crc = high ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)
        }
        return crc
    }

    // MARK: - UDP transport

    private static func sendUDP(
        packet: Data,
        host: String,
        port: UInt16,
        log: (@Sendable (String) -> Void)?
    ) async {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: udpQueue)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    log?("Px4ModeCommander UDP send to \(host):\(port) failed: \(error.localizedDescription)")
                }
                connection.cancel()
                continuation.resume()
            })
        }
    }

    private static let udpQueue = DispatchQueue(label: "guardian.px4.mode-commander.udp", qos: .utility)
}
