import XCTest
@testable import GuardianHQ

final class SimulationSpawnPolicyTests: XCTestCase {
    func test_effectivePlatform_ugvPresets_forcePx4() {
        for preset in [SimulationVehiclePreset.ugvWheeled, .ugvTracked, .ugvLegged] {
            XCTAssertEqual(
                SimulationSpawnPolicy.effectivePlatform(for: preset, requested: .ardupilot),
                .px4,
                "\(preset.rawValue) should always spawn PX4"
            )
        }
    }

    func test_effectivePlatform_nonUgv_preservesRequest() {
        XCTAssertEqual(
            SimulationSpawnPolicy.effectivePlatform(for: .uavMultirotor, requested: .ardupilot),
            .ardupilot
        )
        XCTAssertEqual(
            SimulationSpawnPolicy.effectivePlatform(for: .uavMultirotor, requested: .px4),
            .px4
        )
    }

    func test_trainingPanelSelectableCases_ugvOnly() {
        XCTAssertEqual(
            TrainingVehicleClass.trainingPanelSelectableCases,
            [.ugvWheeled, .ugvTracked]
        )
    }
}
