import XCTest
@testable import GuardianHQ

final class TrainingLabSquadFormationPolicyTests: XCTestCase {
    func test_endFormationChoice_autoResolvesNil() {
        let choice = TrainingLabEndFormationChoice.auto
        XCTAssertNil(choice.resolved)
        XCTAssertEqual(TrainingLabEndFormationChoice(resolved: nil), .auto)
    }

    func test_endFormationChoice_specificRoundTrip() {
        let choice = TrainingLabEndFormationChoice(resolved: .chevron)
        XCTAssertEqual(choice, .chevron)
        XCTAssertEqual(choice.resolved, .chevron)
    }

    func test_endSpacingChoice_autoResolvesNil() {
        XCTAssertNil(TrainingLabEndSpacingChoice.auto.resolved)
        XCTAssertEqual(TrainingLabEndSpacingChoice(resolved: .loose), .loose)
    }

    func test_absorbPrimary_preservesTargetSquadFormationPolicy() {
        var targetPolicy = TrainingLabSquadFormationPolicy.default
        targetPolicy.startFormation = .chevron
        targetPolicy.endFormation = .arrowhead

        let alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let alphaWing = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let betaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvTracked)
        var squads = [
            TrainingLabSquad(primary: alphaPrimary, wingmen: [alphaWing], formationPolicy: targetPolicy),
            TrainingLabSquad(primary: betaPrimary),
        ]
        XCTAssertTrue(
            TrainingLabRosterEditing.absorbPrimaryIntoSquad(
                squads: &squads,
                draggedEntryID: betaPrimary.id,
                targetSquadID: squads[0].id
            )
        )

        XCTAssertEqual(squads[0].formationPolicy, targetPolicy)
        XCTAssertEqual(squads[0].id, squads.first(where: { $0.primary.id == alphaWing.id })?.id)
    }
}
