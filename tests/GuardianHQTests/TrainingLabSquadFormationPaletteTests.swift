import XCTest

@testable import GuardianCore

final class TrainingLabSquadFormationPaletteTests: XCTestCase {
    func test_squad_zero_uses_amber_hex() {
        XCTAssertEqual(TrainingLabSquadFormationPalette.colorHex(squadIndex: 0), "#f59e0b")
    }

    func test_hex_parses_to_gazebo_rgba() {
        let rgba = TrainingLabSquadFormationPalette.rgba(fromHex: "#f59e0b")
        XCTAssertNotNil(rgba)
        XCTAssertEqual(rgba?.r, 245.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgba?.g, 158.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgba?.b, 11.0 / 255.0, accuracy: 0.001)
    }

    func test_gazebo_material_matches_palette_index() {
        let rgba = TrainingLabSquadFormationPalette.gazeboMaterialRGBA(squadIndex: 0)
        XCTAssertEqual(
            rgba.diffuseTriple,
            TrainingLabSquadFormationPalette.rgba(fromHex: "#f59e0b")!.diffuseTriple
        )
    }
}
