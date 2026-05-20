import XCTest

@testable import GuardianCore

final class GazeboVehicleModelSDFWriterTests: XCTestCase {
    func test_box_sdf_uses_universal_class_colour() {
        let footprint = VehicleClassSizeCatalogue.footprint(vehicleClass: .ugvWheeled, tier: .medium)
        let xml = GazeboVehicleModelSDFWriter.modelSDFXML(
            modelName: "guardian_veh_sysid_1",
            footprint: footprint,
            universalClass: .ugv,
            meshFilePath: nil
        )
        XCTAssertTrue(xml.contains("<size>1.6 2.65 1.25</size>"))
        XCTAssertTrue(xml.contains("0.200 0.450 1.000"))
        XCTAssertFalse(xml.contains("<mesh>"))
        XCTAssertFalse(xml.contains("visual_bottom"))
    }

    func test_mesh_sdf_when_readable_path_provided() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GazeboVehicleModelSDFWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let meshURL = dir.appendingPathComponent("body.dae")
        try Data("stub".utf8).write(to: meshURL)

        let params = GazeboVehicleSpawnParams(
            vehicleClass: .uavCopter,
            vehicleSizeTier: .micro,
            pose: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            customMeshURI: meshURL.path
        )
        let written = try GazeboVehicleModelSDFWriter.writeTemporaryModel(
            modelName: "guardian_veh_mesh",
            params: params,
            footprint: VehicleClassSizeCatalogue.footprint(vehicleClass: .uavCopter, tier: .micro)
        )
        XCTAssertTrue(written.usesCustomMesh)
        let xml = try String(contentsOf: written.sdfURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<mesh>"))
        XCTAssertTrue(xml.contains("file://"))
    }

    func test_universal_class_colours_distinct() {
        let uav = GazeboUniversalClassVisualStyle.rgba(for: .uav)
        let ugv = GazeboUniversalClassVisualStyle.rgba(for: .ugv)
        XCTAssertNotEqual(uav.diffuseTriple, ugv.diffuseTriple)
    }
}
