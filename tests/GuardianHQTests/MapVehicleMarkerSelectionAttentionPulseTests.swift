import XCTest

@testable import GuardianCore

final class MapVehicleMarkerSelectionAttentionPulseTests: XCTestCase {

    func test_selection_attention_pulse_participates_in_equatable() {
        let base = MapVehicleMarker(
            id: "pool.x.y",
            lat: 1,
            lon: 2,
            label: "R1 · pool",
            colorHex: "#ffffff",
            selected: true,
            draggable: false,
            selectionAttentionPulse: false,
            headingDeg: nil
        )
        let pulsing = MapVehicleMarker(
            id: "pool.x.y",
            lat: 1,
            lon: 2,
            label: "R1 · pool",
            colorHex: "#ffffff",
            selected: true,
            draggable: false,
            selectionAttentionPulse: true,
            headingDeg: nil
        )
        XCTAssertEqual(base, base)
        XCTAssertNotEqual(base, pulsing)
    }
}
