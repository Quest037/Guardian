import Foundation

/// Run-time validation before Training lab **Run** spawns simulators (formation slots must fit and not overlap).
enum TrainingLabFormationSlotStaging {
    struct Issue: Equatable, Sendable {
        var message: String
    }

    struct Result: Equatable, Sendable {
        var issues: [Issue]

        var isReady: Bool { issues.isEmpty }

        var operatorMessage: String {
            issues.map(\.message).joined(separator: " ")
        }
    }

    static func validate(
        squads: [TrainingLabSquad],
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) -> Result {
        var issues: [Issue] = []
        guard !squads.isEmpty else {
            issues.append(Issue(message: "Add at least one squad before Run."))
            return Result(issues: issues)
        }
        if !zones.start.placed {
            issues.append(Issue(message: "This map has no start zone — rebuild it in Worlds."))
        }
        if !zones.end.placed {
            issues.append(Issue(message: "This map has no end zone — rebuild it in Worlds."))
        }
        if !issues.isEmpty { return Result(issues: issues) }

        let floor = TrainingLabFormationSlotGeometry.mapFloor(halfExtentM: mapHalfExtentM)
        if !WorldBuilderZoneBoundsCheck.zonesFitOnFloor(zones, floor: floor) {
            issues.append(Issue(message: "Start or end zone is off the map edge."))
        }
        if WorldBuilderZoneBoundsCheck.zonesOverlap(zones) {
            issues.append(Issue(message: "Start and end zones overlap — fix the map in Worlds."))
        }
        if !issues.isEmpty { return Result(issues: issues) }

        for phase in [TrainingLabFormationSlotGeometry.ZonePhase.start, .end] {
            let zone = phase == .start ? zones.start : zones.end
            var phaseSlots: [TrainingLabFormationSlotGeometry.Slot] = []
            for (squadIndex, squad) in squads.enumerated() {
                let anchor = resolvedAnchor(squad: squad, squadIndex: squadIndex, phase: phase, zone: zone)
                let layout = TrainingLabFormationSlotGeometry.groupLayout(
                    squad: squad,
                    squadIndex: squadIndex,
                    phase: phase,
                    anchor: anchor
                )
                if !TrainingLabFormationSlotGeometry.groupFitsZone(
                    anchor: layout.anchor,
                    circleRadiusM: layout.circleRadiusM,
                    zone: zone
                ) {
                    let label = TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex)
                    let zoneName = phase == .start ? "start" : "end"
                    issues.append(
                        Issue(
                            message: "\(label) \(zoneName) formation does not fit in the \(zoneName) zone — shrink spacing, use a larger map, or move the group."
                        )
                    )
                }
                for slot in layout.slots where !TrainingLabFormationSlotGeometry.slotFitsZone(slot, zone: zone) {
                    let label = TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex)
                    let zoneName = phase == .start ? "start" : "end"
                    issues.append(
                        Issue(
                            message: "\(label) has a vehicle outside the \(zoneName) zone."
                        )
                    )
                }
                phaseSlots.append(contentsOf: layout.slots)
            }
            for i in phaseSlots.indices {
                for j in (i + 1)..<phaseSlots.count {
                    if TrainingLabFormationSlotGeometry.slotsOverlap(phaseSlots[i], phaseSlots[j]) {
                        let a = phaseSlots[i].squadLabel
                        let b = phaseSlots[j].squadLabel
                        let zoneName = phase == .start ? "start" : "end"
                        issues.append(
                            Issue(
                                message: "\(a) and \(b) \(zoneName) slots overlap — spread squads or use a larger map."
                            )
                        )
                    }
                }
            }
        }
        return Result(issues: issues)
    }

    private static func resolvedAnchor(
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zone: WorldBuilderZoneState
    ) -> TrainingLabZoneFormationAnchor {
        switch phase {
        case .start:
            return squad.startZoneAnchor ?? .defaultForSquadIndex(squadIndex, in: zone)
        case .end:
            return squad.endZoneAnchor ?? .defaultForSquadIndex(squadIndex, in: zone)
        }
    }
}
