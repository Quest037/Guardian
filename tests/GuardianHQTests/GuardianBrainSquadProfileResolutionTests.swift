import XCTest

@testable import GuardianHQ

final class GuardianBrainSquadProfileResolutionTests: XCTestCase {
    func test_tuning_parses_formation_and_spacing_from_export_payload() throws {
        struct ConvoyExportPayload: Codable {
            var simCount: Int
            var alongTrackMetersPerOrdinal: Double
            var lateralLaneMeters: Double
            var shapeScaleAlong: Double
            var shapeScaleLateral: Double
        }
        let payload = ConvoyExportPayload(
            simCount: 3,
            alongTrackMetersPerOrdinal: 4.2,
            lateralLaneMeters: 0.5,
            shapeScaleAlong: MissionSquadFormationShape.tight.alongTrackScale,
            shapeScaleLateral: MissionSquadFormationShape.tight.lateralScale
        )
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let profile = GuardianBrainPackSquadProfile(
            formationShape: MissionSquadFormationKind.arrowhead.rawValue,
            slotSpacingM: 4.2,
            convoyOffsetsJSON: json
        )
        let tuning = GuardianBrainSquadProfileResolution.tuning(from: profile)
        XCTAssertEqual(tuning?.formation, .arrowhead)
        XCTAssertEqual(tuning?.shape, .tight)
        XCTAssertEqual(tuning?.spacing?.alongTrackMetersPerOrdinal, 4.2)
        XCTAssertEqual(tuning?.spacing?.lateralLaneMeters, 0.5)
    }

    func test_inferredShape_picks_closest_pack_tightness() {
        XCTAssertEqual(
            GuardianBrainSquadProfileResolution.inferredShape(
                alongScale: MissionSquadFormationShape.loose.alongTrackScale,
                lateralScale: MissionSquadFormationShape.loose.lateralScale
            ),
            .loose
        )
    }
}
