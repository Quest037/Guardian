import XCTest

@testable import GuardianHQ

final class GuardianBrainPackBuilderSquadProfileTests: XCTestCase {
    func test_squadProfile_encodes_formation_metadata() throws {
        let profile = GuardianBrainPackBuilder.squadProfile(
            formation: .arrowhead,
            shape: .tight,
            vehicleClass: .ugvWheeled,
            simCount: 4
        )
        XCTAssertEqual(profile.formationShape, MissionSquadFormationKind.arrowhead.rawValue)
        XCTAssertNotNil(profile.slotSpacingM)
        XCTAssertNotNil(profile.convoyOffsetsJSON)
        XCTAssertTrue(profile.convoyOffsetsJSON?.contains("simCount") == true)
    }

    func test_makePack_retains_squad_profile() throws {
        let skill = TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.forward(0.5, durationS: 1)],
            score: TrainingSkillScore(
                positionErrorM: 0.2,
                headingErrorDeg: 1,
                episodeDurationS: 5,
                constraintViolations: [],
                succeeded: true
            ),
            layout: TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default),
            trialIndex: 0,
            summary: "test"
        )
        let profile = GuardianBrainPackBuilder.squadProfile(
            formation: .convoy,
            shape: .normal,
            vehicleClass: .ugvWheeled,
            simCount: 3
        )
        let pack = try GuardianBrainPackBuilder.makePack(
            from: skill,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test",
            squadProfile: profile
        )
        XCTAssertEqual(pack.squadProfile, profile)
    }
}
