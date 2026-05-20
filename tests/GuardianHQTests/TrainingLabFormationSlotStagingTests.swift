import XCTest
@testable import GuardianCore

final class TrainingLabFormationSlotStagingTests: XCTestCase {
    func test_validate_flags_overlapping_start_slots_from_two_squads() {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 40,
            shape: .circle
        )
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 30,
            centerYM: 0,
            centerZM: 0,
            radiusM: 40,
            shape: .circle
        )
        let anchor = TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0)
        let squadA = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            wingmen: [TrainingLabRosterEntry(vehicleClass: .ugvWheeled)],
            startZoneAnchor: anchor,
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 30, centerYM: 0, headingDeg: 0)
        )
        let squadB = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: anchor,
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 30, centerYM: 0, headingDeg: 0)
        )
        let result = TrainingLabFormationSlotStaging.validate(
            squads: [squadA, squadB],
            zones: zones,
            mapHalfExtentM: 50
        )
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.operatorMessage.contains("overlap"))
    }

    func test_validate_passes_single_squad_on_micro_map() {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: -20,
            centerYM: 0,
            centerZM: 0,
            radiusM: 20,
            shape: .circle
        )
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 20,
            centerYM: 0,
            centerZM: 0,
            radiusM: 20,
            shape: .circle
        )
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: -20, centerYM: 0, headingDeg: 0),
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 20, centerYM: 0, headingDeg: 0)
        )
        let result = TrainingLabFormationSlotStaging.validate(
            squads: [squad],
            zones: zones,
            mapHalfExtentM: 50
        )
        XCTAssertTrue(result.isReady, result.operatorMessage)
    }

    func test_groupLayout_slot_count_follows_roster_entries() {
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            wingmen: [
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            ]
        )
        let layout = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squad,
            squadIndex: 0,
            phase: .start,
            anchor: TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0)
        )
        XCTAssertEqual(layout.slots.count, 3)
    }
}
