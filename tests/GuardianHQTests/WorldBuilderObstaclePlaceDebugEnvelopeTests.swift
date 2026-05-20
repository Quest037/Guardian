import XCTest
@testable import GuardianCore

/// Decodes gzweb → Swift obstacle placement debug payloads (see `guardian_viewer.html`).
final class WorldBuilderObstaclePlaceDebugEnvelopeTests: XCTestCase {
    private struct Envelope: Decodable {
        var type: String
        var message: String?
        var centerXM: Double?
        var centerYM: Double?
    }

    func test_decode_obstaclePlaceDebug() throws {
        let json = #"{"type":"obstaclePlaceDebug","message":"tryPlace — placementActive=false"}"#
        let envelope = try JSONDecoder().decode(Envelope.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(envelope.type, "obstaclePlaceDebug")
        XCTAssertEqual(envelope.message, "tryPlace — placementActive=false")
    }

    func test_decode_placeObstacle() throws {
        let json = #"{"type":"placeObstacle","centerXM":12.5,"centerYM":-3.25}"#
        let envelope = try JSONDecoder().decode(Envelope.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(envelope.type, "placeObstacle")
        XCTAssertEqual(envelope.centerXM ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(envelope.centerYM ?? 0, -3.25, accuracy: 0.001)
    }
}
