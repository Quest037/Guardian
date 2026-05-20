import Foundation

/// ENU formation slot layout, zone fit, and overlap checks for Training lab squad zones.
enum TrainingLabFormationSlotGeometry {
    static let slotGroupCircleMinRadiusM: Double = 6
    static let slotGroupCirclePaddingM: Double = 2
    static let slotOverlapSeparationM: Double = 0.35

    enum ZonePhase: String, Codable, Sendable {
        case start
        case end
    }

    struct Slot: Equatable, Sendable {
        var squadID: UUID
        var squadLabel: String
        var squadIndex: Int
        var slotIndex: Int
        var isPrimary: Bool
        var centerXM: Double
        var centerYM: Double
        var headingDeg: Double
        var widthM: Double
        var lengthM: Double
        var colorHex: String
    }

    struct GroupLayout: Equatable, Sendable {
        var anchor: TrainingLabZoneFormationAnchor
        var circleRadiusM: Double
        var slots: [Slot]
    }

    // MARK: - Policy

    static func resolvedEndFormation(_ policy: TrainingLabSquadFormationPolicy) -> MissionSquadFormationKind {
        policy.endFormation ?? policy.startFormation
    }

    static func resolvedEndSpacing(_ policy: TrainingLabSquadFormationPolicy) -> MissionSquadFormationSpacing {
        policy.endSpacing ?? policy.startSpacing
    }

    static func formation(
        for phase: ZonePhase,
        policy: TrainingLabSquadFormationPolicy
    ) -> MissionSquadFormationKind {
        switch phase {
        case .start: return policy.startFormation
        case .end: return resolvedEndFormation(policy)
        }
    }

    static func spacing(
        for phase: ZonePhase,
        policy: TrainingLabSquadFormationPolicy
    ) -> MissionSquadFormationSpacing {
        switch phase {
        case .start: return policy.startSpacing
        case .end: return resolvedEndSpacing(policy)
        }
    }

    // MARK: - Layout

    static func groupLayout(
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: ZonePhase,
        anchor: TrainingLabZoneFormationAnchor
    ) -> GroupLayout {
        let formation = formation(for: phase, policy: squad.formationPolicy)
        let spacingKind = spacing(for: phase, policy: squad.formationPolicy)
        let convoySpacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: squad.primary.vehicleClass.fleetVehicleType,
            spacing: spacingKind,
            formation: formation
        )
        let colorHex = TrainingLabSquadFormationPalette.colorHex(squadIndex: squadIndex)
        var slots: [Slot] = []
        let entries = squad.allEntries
        for (index, entry) in entries.enumerated() {
            let offset = bodyOffsetMeters(
                formation: formation,
                wingmanOrdinal: index == 0 ? nil : index - 1,
                spacing: convoySpacing
            )
            let center = enuOffset(
                anchorXM: anchor.centerXM,
                anchorYM: anchor.centerYM,
                headingDeg: anchor.headingDeg,
                forwardM: offset.forwardM,
                rightM: offset.rightM
            )
            let footprint = VehicleClassSizeCatalogue.footprintMetres(
                vehicleClass: entry.vehicleClass.fleetVehicleType,
                tier: entry.vehicleSizeTier
            )
            slots.append(
                Slot(
                    squadID: squad.id,
                    squadLabel: TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex),
                    squadIndex: squadIndex,
                    slotIndex: index,
                    isPrimary: index == 0,
                    centerXM: center.x,
                    centerYM: center.y,
                    headingDeg: anchor.headingDeg,
                    widthM: footprint.widthM,
                    lengthM: footprint.lengthM,
                    colorHex: colorHex
                )
            )
        }
        let circleRadiusM = formationGroupCircleRadiusM(
            anchor: anchor,
            formation: formation,
            spacing: convoySpacing,
            slots: slots
        )
        return GroupLayout(anchor: anchor, circleRadiusM: circleRadiusM, slots: slots)
    }

    static func formationGroupCircleRadiusM(
        anchor: TrainingLabZoneFormationAnchor,
        formation: MissionSquadFormationKind,
        spacing: MissionSquadConvoySpacing,
        slots: [Slot]
    ) -> Double {
        var maxM = slotGroupCircleMinRadiusM
        for slot in slots where slot.slotIndex > 0 {
            let offset = bodyOffsetMeters(
                formation: formation,
                wingmanOrdinal: slot.slotIndex - 1,
                spacing: spacing
            )
            let center = enuOffset(
                anchorXM: anchor.centerXM,
                anchorYM: anchor.centerYM,
                headingDeg: anchor.headingDeg,
                forwardM: offset.forwardM,
                rightM: offset.rightM
            )
            let dx = center.x - anchor.centerXM
            let dy = center.y - anchor.centerYM
            let d = (dx * dx + dy * dy).squareRoot()
            maxM = max(maxM, d)
        }
        let footprintPad = slots.map { overlapRadiusM(widthM: $0.widthM, lengthM: $0.lengthM) }.max() ?? 0
        return max(slotGroupCircleMinRadiusM, maxM + footprintPad + slotGroupCirclePaddingM)
    }

    // MARK: - Fit / overlap

    static func mapFloor(halfExtentM: Double) -> WorldBuilderZoneFloorRect {
        WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: halfExtentM)
    }

    static func pointInsideZone(x: Double, y: Double, zone: WorldBuilderZoneState, epsilon: Double = 1e-6) -> Bool {
        guard zone.placed else { return false }
        switch zone.shape {
        case .square:
            return abs(x - zone.centerXM) <= zone.radiusM + epsilon
                && abs(y - zone.centerYM) <= zone.radiusM + epsilon
        case .circle:
            let dx = x - zone.centerXM
            let dy = y - zone.centerYM
            return (dx * dx + dy * dy).squareRoot() <= zone.radiusM + epsilon
        }
    }

    static func groupFitsZone(
        anchor: TrainingLabZoneFormationAnchor,
        circleRadiusM: Double,
        zone: WorldBuilderZoneState
    ) -> Bool {
        guard zone.placed else { return false }
        let sampleCount = 16
        for i in 0..<sampleCount {
            let t = (Double(i) / Double(sampleCount)) * 2 * Double.pi
            let x = anchor.centerXM + cos(t) * circleRadiusM
            let y = anchor.centerYM + sin(t) * circleRadiusM
            if !pointInsideZone(x: x, y: y, zone: zone) {
                return false
            }
        }
        return pointInsideZone(x: anchor.centerXM, y: anchor.centerYM, zone: zone)
    }

    static func slotFitsZone(_ slot: Slot, zone: WorldBuilderZoneState) -> Bool {
        guard zone.placed else { return false }
        for corner in orientedFootprintCorners(slot: slot) {
            if !pointInsideZone(x: corner.x, y: corner.y, zone: zone) {
                return false
            }
        }
        return true
    }

    static func slotsOverlap(_ a: Slot, _ b: Slot) -> Bool {
        let dx = a.centerXM - b.centerXM
        let dy = a.centerYM - b.centerYM
        let dist = (dx * dx + dy * dy).squareRoot()
        let minDist = overlapRadiusM(widthM: a.widthM, lengthM: a.lengthM)
            + overlapRadiusM(widthM: b.widthM, lengthM: b.lengthM)
        return dist < minDist - slotOverlapSeparationM
    }

    static func clampAnchor(
        _ anchor: inout TrainingLabZoneFormationAnchor,
        circleRadiusM: Double,
        zone: WorldBuilderZoneState,
        mapHalfExtentM: Double
    ) {
        guard zone.placed else { return }
        let floor = mapFloor(halfExtentM: mapHalfExtentM)
        anchor.centerXM = min(max(anchor.centerXM, floor.minXM + circleRadiusM), floor.maxXM - circleRadiusM)
        anchor.centerYM = min(max(anchor.centerYM, floor.minYM + circleRadiusM), floor.maxYM - circleRadiusM)
        if !groupFitsZone(anchor: anchor, circleRadiusM: circleRadiusM, zone: zone) {
            anchor.centerXM = zone.centerXM
            anchor.centerYM = zone.centerYM
        }
        anchor.headingDeg = normalizedHeadingDeg(anchor.headingDeg)
    }

    // MARK: - Private

    private static func bodyOffsetMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int?,
        spacing: MissionSquadConvoySpacing
    ) -> MissionSquadFormationGeometry.BodyOffsetMeters {
        if let wingmanOrdinal {
            return MissionSquadFormationGeometry.bodyOffsetMeters(
                formation: formation,
                wingmanOrdinal: wingmanOrdinal,
                spacing: spacing
            )
        }
        return MissionSquadFormationGeometry.BodyOffsetMeters(forwardM: 0, rightM: 0)
    }

    private static func enuOffset(
        anchorXM: Double,
        anchorYM: Double,
        headingDeg: Double,
        forwardM: Double,
        rightM: Double
    ) -> (x: Double, y: Double) {
        let h = headingDeg * .pi / 180
        let sinH = sin(h)
        let cosH = cos(h)
        let eastM = forwardM * sinH + rightM * cosH
        let northM = forwardM * cosH - rightM * sinH
        return (anchorXM + eastM, anchorYM + northM)
    }

    private static func overlapRadiusM(widthM: Double, lengthM: Double) -> Double {
        0.5 * hypot(widthM, lengthM)
    }

    private static func orientedFootprintCorners(slot: Slot) -> [(x: Double, y: Double)] {
        let halfL = slot.lengthM * 0.5
        let halfW = slot.widthM * 0.5
        let local: [(Double, Double)] = [
            (halfL, halfW),
            (halfL, -halfW),
            (-halfL, -halfW),
            (-halfL, halfW),
        ]
        let h = slot.headingDeg * .pi / 180
        let sinH = sin(h)
        let cosH = cos(h)
        return local.map { (fx, fy) in
            let east = fx * sinH + fy * cosH
            let north = fx * cosH - fy * sinH
            return (slot.centerXM + east, slot.centerYM + north)
        }
    }

    private static func normalizedHeadingDeg(_ heading: Double) -> Double {
        var h = heading.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }
}
