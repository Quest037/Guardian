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

    func test_formation_slot_payload_includes_start_and_end_groups_when_zones_placed() {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: -25,
            centerYM: 0,
            centerZM: 0,
            radiusM: 25,
            shape: .square
        )
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 25,
            centerYM: 0,
            centerZM: 0,
            radiusM: 25,
            shape: .square
        )
        var primary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        primary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-ugv",
            linkReady: true,
            preflightPassed: true
        )
        let squad = TrainingLabSquad(primary: primary)
        let snapshot = TrainingLabRosterStore.snapshot(from: [squad], learningSquadID: squad.id)
        let restored = TrainingLabRosterStore.squads(from: snapshot)
        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(restored[0].hasLinkedSimulator)

        let layoutStart = TrainingLabFormationSlotGeometry.groupLayout(
            squad: restored[0],
            squadIndex: 0,
            phase: .start,
            anchor: restored[0].startZoneAnchor ?? .seeded(in: zones.start)
        )
        let layoutEnd = TrainingLabFormationSlotGeometry.groupLayout(
            squad: restored[0],
            squadIndex: 0,
            phase: .end,
            anchor: restored[0].endZoneAnchor ?? .seeded(in: zones.end)
        )
        XCTAssertEqual(layoutStart.slots.count, 1)
        XCTAssertEqual(layoutEnd.slots.count, 1)
        XCTAssertTrue(zones.start.placed)
        XCTAssertTrue(zones.end.placed)
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

    func test_groupFitsZoneFromSlots_passes_convoy_at_zone_centre() {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 40,
            shape: .circle
        )
        var policy = TrainingLabSquadFormationPolicy()
        policy.startFormation = .convoy
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            wingmen: [
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            ],
            formationPolicy: policy
        )
        let anchor = TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0)
        let layout = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squad,
            squadIndex: 0,
            phase: .start,
            anchor: anchor
        )
        XCTAssertTrue(
            TrainingLabFormationSlotGeometry.groupFitsZoneFromSlots(layout.slots, zone: zones.start)
        )
    }

    func test_chevron_layout_offsets_wingmen_laterally_from_convoy() {
        let anchor = TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0)
        let wingmen = [TrainingLabRosterEntry(vehicleClass: .ugvWheeled)]
        var convoyPolicy = TrainingLabSquadFormationPolicy()
        convoyPolicy.startFormation = .convoy
        let convoy = TrainingLabFormationSlotGeometry.groupLayout(
            squad: TrainingLabSquad(
                primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                wingmen: wingmen,
                formationPolicy: convoyPolicy
            ),
            squadIndex: 0,
            phase: .start,
            anchor: anchor
        )
        var chevronPolicy = TrainingLabSquadFormationPolicy()
        chevronPolicy.startFormation = .chevron
        let chevron = TrainingLabFormationSlotGeometry.groupLayout(
            squad: TrainingLabSquad(
                primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                wingmen: wingmen,
                formationPolicy: chevronPolicy
            ),
            squadIndex: 0,
            phase: .start,
            anchor: anchor
        )
        let convoyWing = convoy.slots[1]
        let chevronWing = chevron.slots[1]
        let convoyLateral = abs(convoyWing.centerXM - anchor.centerXM)
        let chevronLateral = abs(chevronWing.centerXM - anchor.centerXM)
        XCTAssertGreaterThan(chevronLateral, convoyLateral + 0.5)
    }
}
