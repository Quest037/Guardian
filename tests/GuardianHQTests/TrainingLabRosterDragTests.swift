import XCTest
@testable import GuardianHQ

final class TrainingLabRosterDragTests: XCTestCase {
    func test_absorbPrimaryIntoSquad_promotesFirstWingmanWhenSourceHadWingmen() {
        let alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let alphaWing = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let betaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvTracked)
        var squads = [
            TrainingLabSquad(primary: alphaPrimary, wingmen: [alphaWing]),
            TrainingLabSquad(primary: betaPrimary),
        ]
        let alphaID = squads[0].id
        let betaID = squads[1].id

        XCTAssertTrue(
            TrainingLabRosterEditing.absorbPrimaryIntoSquad(
                squads: &squads,
                draggedEntryID: alphaPrimary.id,
                targetSquadID: betaID
            )
        )

        XCTAssertEqual(squads.count, 2)
        XCTAssertEqual(squads[0].id, alphaID)
        XCTAssertEqual(squads[0].primary.id, alphaWing.id)
        XCTAssertTrue(squads[0].wingmen.isEmpty)
        XCTAssertEqual(squads[1].id, betaID)
        XCTAssertEqual(squads[1].wingmen.map(\.id), [alphaPrimary.id])
    }

    func test_moveWingmanToSquad_appendsToTarget() {
        let alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let alphaWing = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let betaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvTracked)
        var squads = [
            TrainingLabSquad(primary: alphaPrimary, wingmen: [alphaWing]),
            TrainingLabSquad(primary: betaPrimary),
        ]
        let betaID = squads[1].id

        XCTAssertTrue(
            TrainingLabRosterEditing.moveWingmanToSquad(
                squads: &squads,
                entryID: alphaWing.id,
                targetSquadID: betaID
            )
        )

        XCTAssertTrue(squads[0].wingmen.isEmpty)
        XCTAssertEqual(squads[1].wingmen.map(\.id), [alphaWing.id])
    }

    func test_promoteWingmanToNewSquad_preservesSourceSquadPolicy() {
        var alphaPolicy = TrainingLabSquadFormationPolicy.default
        alphaPolicy.startSpacing = .loose
        let alphaPrimary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        let alphaWing = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        var squads = [
            TrainingLabSquad(primary: alphaPrimary, wingmen: [alphaWing], formationPolicy: alphaPolicy),
        ]
        let alphaID = squads[0].id

        let wingman = squads[0].wingmen.removeFirst()
        squads.append(TrainingLabSquad(primary: wingman))

        XCTAssertEqual(squads[0].id, alphaID)
        XCTAssertEqual(squads[0].formationPolicy, alphaPolicy)
        XCTAssertEqual(squads[1].formationPolicy, .default)
    }
}
