import Foundation
import Network

/// Minimal MAVLink v2 `COMMAND_LONG` sender for autopilot commands that MAVSDK Swift
/// does not expose. This is intentionally small: it sends one packet and lets the
/// existing command pipeline watch telemetry / follow-up recipe steps for confirmation.
enum MavlinkCommandLongSender {
    static func send(
        request: MavlinkCommandLongRequest,
        host: String = "127.0.0.1",
        port: UInt16,
        targetSystem: UInt8,
        sourceSystem: UInt8 = 255,
        sourceComponent: UInt8 = 0
    ) async throws {
        let packet = buildCommandLongPacket(
            request: request,
            targetSystem: targetSystem,
            sourceSystem: sourceSystem,
            sourceComponent: sourceComponent,
            sequence: nextSequence()
        )
        try await sendUDP(packet: packet, host: host, port: port)
    }

    private static func buildCommandLongPacket(
        request: MavlinkCommandLongRequest,
        targetSystem: UInt8,
        sourceSystem: UInt8,
        sourceComponent: UInt8,
        sequence: UInt8
    ) -> Data {
        // COMMAND_LONG payload order is defined by MAVLink's field reordering:
        // 7 float params, command uint16, then target_system / target_component /
        // confirmation uint8 fields.
        var payload = Data(capacity: 33)
        payload.appendLittleEndian(request.param1)
        payload.appendLittleEndian(request.param2)
        payload.appendLittleEndian(request.param3)
        payload.appendLittleEndian(request.param4)
        payload.appendLittleEndian(request.param5)
        payload.appendLittleEndian(request.param6)
        payload.appendLittleEndian(request.param7)
        payload.appendLittleEndian(request.command)
        payload.append(targetSystem)
        payload.append(request.targetComponent)
        payload.append(request.confirmation)

        return assemblePacketV2(
            messageId: 76,
            payload: payload,
            crcExtra: 152,
            systemId: sourceSystem,
            componentId: sourceComponent,
            sequence: sequence
        )
    }

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

    private static let sequenceLock = NSLock()
    nonisolated(unsafe) private static var sequenceCounter: UInt8 = 0

    private static func nextSequence() -> UInt8 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        sequenceCounter = sequenceCounter &+ 1
        return sequenceCounter
    }

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

    private static func sendUDP(packet: Data, host: String, port: UInt16) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: udpQueue)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                connection.cancel()
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static let udpQueue = DispatchQueue(label: "guardian.mavlink.command-long.udp", qos: .utility)
}

struct MavlinkCommandLongRequest: Equatable, Sendable {
    var command: UInt16
    var param1: Float = 0
    var param2: Float = 0
    var param3: Float = 0
    var param4: Float = 0
    var param5: Float = 0
    var param6: Float = 0
    var param7: Float = 0
    var targetComponent: UInt8 = 1
    var confirmation: UInt8 = 0
    var humanLabel: String
}

extension MavlinkCommandLongRequest {
    static func preflightCalibration(
        humanLabel: String,
        param1: Float = 0,
        param2: Float = 0,
        param3: Float = 0,
        param4: Float = 0,
        param5: Float = 0,
        param6: Float = 0,
        param7: Float = 0
    ) -> Self {
        Self(
            command: 241,
            param1: param1,
            param2: param2,
            param3: param3,
            param4: param4,
            param5: param5,
            param6: param6,
            param7: param7,
            humanLabel: humanLabel
        )
    }

    static func startMagCalibration(humanLabel: String = "start magnetometer calibration") -> Self {
        Self(
            command: 42424,
            param1: 0, // all compasses
            param2: 1, // retry on failure
            param3: 1, // autosave when accepted / completed
            humanLabel: humanLabel
        )
    }

    static func acceptMagCalibration(humanLabel: String = "accept magnetometer calibration") -> Self {
        Self(command: 42425, param1: 0, humanLabel: humanLabel)
    }

    static func cancelMagCalibration(humanLabel: String = "cancel magnetometer calibration") -> Self {
        Self(command: 42426, param1: 0, humanLabel: humanLabel)
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: Float) {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
