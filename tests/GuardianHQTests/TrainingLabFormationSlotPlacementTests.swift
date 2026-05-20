import XCTest
@testable import GuardianCore

final class TrainingLabFormationSlotPlacementTests: XCTestCase {
    private func squareZone(radiusM: Double = 40) -> WorldBuilderZonesSnapshot {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: radiusM,
            shape: .square
        )
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 60,
            centerYM: 0,
            centerZM: 0,
            radiusM: radiusM,
            shape: .square
        )
        return zones
    }

    func test_groupLayout_slot_centers_match_mission_squad_geometry() {
        var policy = TrainingLabSquadFormationPolicy()
        policy.startFormation = .arrowhead
        policy.startSpacing = .normal
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            wingmen: [
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
                TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            ],
            formationPolicy: policy
        )
        let anchor = TrainingLabZoneFormationAnchor(centerXM: 12, centerYM: -4, headingDeg: 25)
        let layout = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squad,
            squadIndex: 0,
            phase: .start,
            anchor: anchor
        )
        let convoySpacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: squad.primary.vehicleClass.fleetVehicleType,
            spacing: policy.startSpacing,
            formation: policy.startFormation
        )
        for (index, slot) in layout.slots.enumerated() {
            let body = index == 0
                ? MissionSquadFormationGeometry.BodyOffsetMeters(forwardM: 0, rightM: 0)
                : MissionSquadFormationGeometry.bodyOffsetMeters(
                    formation: policy.startFormation,
                    wingmanOrdinal: index - 1,
                    spacing: convoySpacing
                )
            let expected = MissionSquadFormationGeometry.enuMetersFromBodyOffset(
                originXM: anchor.centerXM,
                originYM: anchor.centerYM,
                headingDeg: anchor.headingDeg,
                forwardM: body.forwardM,
                rightM: body.rightM
            )
            XCTAssertEqual(slot.centerXM, expected.x, accuracy: 1e-6, "slot \(index) X")
            XCTAssertEqual(slot.centerYM, expected.y, accuracy: 1e-6, "slot \(index) Y")
        }
    }

    func test_resolve_snaps_drop_away_from_overlapping_peer() {
        let zones = squareZone()
        let shared = TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0)
        let squadA = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: shared
        )
        let squadB = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: shared
        )
        let squads = [squadA, squadB]
        let resolved = TrainingLabFormationSlotPlacement.resolveAnchorAfterMapDrag(
            proposed: shared,
            prior: shared,
            squad: squadB,
            squadIndex: 1,
            phase: .start,
            squads: squads,
            zones: zones,
            mapHalfExtentM: 80
        )
        XCTAssertTrue(resolved.adjustedFromDrop)
        let layoutA = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squadA,
            squadIndex: 0,
            phase: .start,
            anchor: squadA.startZoneAnchor ?? shared
        )
        let layoutB = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squadB,
            squadIndex: 1,
            phase: .start,
            anchor: resolved.anchor
        )
        for a in layoutA.slots {
            for b in layoutB.slots {
                XCTAssertFalse(TrainingLabFormationSlotGeometry.slotsOverlap(a, b))
            }
        }
    }

    func test_resolve_keeps_valid_drop_without_adjustment() {
        let zones = squareZone()
        let anchor = TrainingLabZoneFormationAnchor(centerXM: -10, centerYM: 5, headingDeg: 0)
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: anchor
        )
        let resolved = TrainingLabFormationSlotPlacement.resolveAnchorAfterMapDrag(
            proposed: anchor,
            prior: anchor,
            squad: squad,
            squadIndex: 0,
            phase: .start,
            squads: [squad],
            zones: zones,
            mapHalfExtentM: 80
        )
        XCTAssertFalse(resolved.adjustedFromDrop)
        XCTAssertEqual(resolved.anchor.centerXM, anchor.centerXM, accuracy: 1e-6)
        XCTAssertEqual(resolved.anchor.centerYM, anchor.centerYM, accuracy: 1e-6)
    }
}
