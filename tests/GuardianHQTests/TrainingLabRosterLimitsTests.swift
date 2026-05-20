import XCTest
@testable import GuardianCore

final class TrainingLabRosterLimitsTests: XCTestCase {
    func test_defaultAnchor_offsets_differ_for_three_squad_indices_square() {
        let zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 10,
            centerYM: -5,
            centerZM: 0,
            radiusM: 30,
            shape: .square
        )
        let a = TrainingLabZoneFormationAnchor.defaultForSquadIndex(0, in: zone)
        let b = TrainingLabZoneFormationAnchor.defaultForSquadIndex(1, in: zone)
        let c = TrainingLabZoneFormationAnchor.defaultForSquadIndex(2, in: zone)
        XCTAssertLessThan(a.centerXM, b.centerXM)
        XCTAssertLessThan(b.centerXM, c.centerXM)
        XCTAssertEqual(b.centerYM, zone.centerYM, accuracy: 1e-6)
    }

    func test_defaultAnchor_offsets_differ_for_three_squad_indices_circle() {
        let zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 24,
            shape: .circle
        )
        let a = TrainingLabZoneFormationAnchor.defaultForSquadIndex(0, in: zone)
        let b = TrainingLabZoneFormationAnchor.defaultForSquadIndex(1, in: zone)
        let c = TrainingLabZoneFormationAnchor.defaultForSquadIndex(2, in: zone)
        XCTAssertGreaterThan(hypot(a.centerXM - b.centerXM, a.centerYM - b.centerYM), 8)
        XCTAssertGreaterThan(hypot(c.centerXM - b.centerXM, c.centerYM - b.centerYM), 8)
    }

    func test_limits_are_locked_values() {
        XCTAssertEqual(TrainingLabRosterLimits.maxSquads, 3)
        XCTAssertEqual(TrainingLabRosterLimits.maxVehiclesPerSquad, 6)
    }
}
