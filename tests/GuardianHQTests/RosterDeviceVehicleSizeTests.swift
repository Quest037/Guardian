import XCTest

@testable import GuardianHQ

final class RosterDeviceVehicleSizeTests: XCTestCase {
    func test_decode_missing_vehicleSizeTier_defaults_to_medium() throws {
        let json = """
        {
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "name": "Alpha",
          "role": "none",
          "slot": "primary",
          "vehicleClass": "ugvWheeled"
        }
        """
        let device = try JSONDecoder().decode(
            RosterDevice.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(device.vehicleSizeTier, .medium)
        XCTAssertEqual(
            device.resolvedFootprint,
            VehicleClassSizeCatalogue.footprint(vehicleClass: .ugvWheeled, tier: .medium)
        )
    }

    func test_encode_roundTrips_vehicleSizeTier() throws {
        let device = RosterDevice(
            name: "Bravo",
            role: .scout,
            slot: .primary,
            vehicleClass: .ugvTracked,
            vehicleSizeTier: .xlarge
        )
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(RosterDevice.self, from: data)
        XCTAssertEqual(decoded.vehicleSizeTier, .xlarge)
        XCTAssertEqual(decoded.resolvedFootprint.widthCm, 385)
    }
}
