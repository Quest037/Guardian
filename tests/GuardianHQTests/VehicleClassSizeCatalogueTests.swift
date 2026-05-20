import CryptoKit
import XCTest

@testable import GuardianCore

final class VehicleClassSizeCatalogueTests: XCTestCase {
    func test_matrix_source_hash_matches_generated_prefix() throws {
        let matrixURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/vehicle_size_matrix.md")
        let data = try Data(contentsOf: matrixURL)
        let digest = SHA256.hash(data: data)
        let prefix = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        XCTAssertEqual(
            String(prefix),
            VehicleClassSizeCatalogue.matrixSHA256Prefix,
            "Regenerate catalogue: python3 scripts/generate_vehicle_class_size_catalogue.py"
        )
    }

    func test_pinned_midpoints_ugv_w_medium_uav_c_micro_ugv_t_xlarge() {
        let ugvW = VehicleClassSizeCatalogue.footprint(vehicleClass: .ugvWheeled, tier: .medium)
        XCTAssertEqual(ugvW, VehicleFootprint(widthCm: 160, lengthCm: 265, heightCm: 125))

        let uavC = VehicleClassSizeCatalogue.footprint(vehicleClass: .uavCopter, tier: .micro)
        XCTAssertEqual(uavC, VehicleFootprint(widthCm: 12, lengthCm: 12, heightCm: 6))

        let ugvT = VehicleClassSizeCatalogue.footprint(vehicleClass: .ugvTracked, tier: .xlarge)
        XCTAssertEqual(ugvT, VehicleFootprint(widthCm: 385, lengthCm: 775, heightCm: 290))
    }

    func test_max_horizontal_axis_increases_across_tiers_for_ugv_wheeled() {
        let axes = VehicleSizeTier.allCases.map {
            VehicleClassSizeCatalogue.footprint(vehicleClass: .ugvWheeled, tier: $0).maxHorizontalAxisCm
        }
        for index in 1..<axes.count {
            XCTAssertGreaterThanOrEqual(axes[index], axes[index - 1])
        }
    }

    func test_unknown_class_uses_conservative_fallback() {
        let fp = VehicleClassSizeCatalogue.footprint(vehicleClass: .unknown, tier: .micro)
        XCTAssertEqual(fp.widthCm, 200)
        XCTAssertEqual(fp.lengthCm, 300)
        XCTAssertEqual(fp.heightCm, 120)
    }

    func test_footprint_metres_scales_from_cm() {
        let metres = VehicleClassSizeCatalogue.footprintMetres(vehicleClass: .ugvWheeled, tier: .medium)
        XCTAssertEqual(metres.widthM, 1.6, accuracy: 0.001)
        XCTAssertEqual(metres.lengthM, 2.65, accuracy: 0.001)
        XCTAssertEqual(metres.heightM, 1.25, accuracy: 0.001)
    }

    func test_gazebo_footprint_from_catalogue() {
        let box = VehicleGazeboFootprint.resolve(vehicleClass: .ugvWheeled, tier: .medium)
        XCTAssertEqual(box.widthM, 1.6, accuracy: 0.001)
        XCTAssertEqual(box.lengthM, 2.65, accuracy: 0.001)
    }

    @MainActor
    func test_preferences_store_resolves_vehicle_override() {
        let store = VehicleClassSizePreferencesStore.shared
        let vehicleID = "sysid:test-size-tier"
        store.clearVehicleOverride(forVehicleID: vehicleID)
        store.setDefaultTier(.medium, for: .ugvWheeled)
        store.setTier(.xlarge, forVehicleID: vehicleID)
        let tier = store.resolvedTier(vehicleID: vehicleID, vehicleClass: .ugvWheeled)
        XCTAssertEqual(tier, .xlarge)
        let fp = store.resolvedFootprint(vehicleID: vehicleID, vehicleClass: .ugvWheeled)
        XCTAssertEqual(fp.maxHorizontalAxisCm, 775)
        store.clearVehicleOverride(forVehicleID: vehicleID)
    }
}
