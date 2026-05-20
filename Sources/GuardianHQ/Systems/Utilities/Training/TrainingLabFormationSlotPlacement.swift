import Foundation

/// Resolves a squad formation anchor after map drag — nearest valid pose (zone + footprint overlap).
enum TrainingLabFormationSlotPlacement {
    struct Result: Equatable, Sendable {
        var anchor: TrainingLabZoneFormationAnchor
        /// `true` when the committed anchor differs from the operator drop (snap / separation).
        var adjustedFromDrop: Bool
    }

    private static let searchStepM: Double = 0.75
    private static let searchMaxRadiusM: Double = 48
    private static let repulsionIterations: Int = 40
    private static let anchorMatchEpsilonM: Double = 0.08

    static func resolveAnchorAfterMapDrag(
        proposed: TrainingLabZoneFormationAnchor,
        prior: TrainingLabZoneFormationAnchor?,
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        squads: [TrainingLabSquad],
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) -> Result {
        let zone = phase == .start ? zones.start : zones.end
        guard zone.placed else {
            return Result(anchor: normalized(proposed), adjustedFromDrop: false)
        }

        let target = normalized(proposed)
        let otherSlots = peerSlots(
            squads: squads,
            excludingSquadID: squad.id,
            phase: phase,
            zones: zones
        )

        if let exact = firstValidAnchor(
            candidates: [target],
            squad: squad,
            squadIndex: squadIndex,
            phase: phase,
            zone: zone,
            otherSlots: otherSlots,
            mapHalfExtentM: mapHalfExtentM
        ), anchorsMatch(exact, target) {
            return Result(anchor: exact, adjustedFromDrop: false)
        }

        var candidates: [TrainingLabZoneFormationAnchor] = [target]
        candidates.append(contentsOf: spiralOffsets(around: target, stepM: searchStepM, maxRadiusM: searchMaxRadiusM))
        if let prior, !anchorsMatch(prior, target) {
            candidates.append(prior)
        }
        candidates.append(.defaultForSquadIndex(squadIndex, in: zone))

        let sorted = candidates.sorted { anchorDistanceSquared($0, target) < anchorDistanceSquared($1, target) }
        if let best = firstValidAnchor(
            candidates: sorted,
            squad: squad,
            squadIndex: squadIndex,
            phase: phase,
            zone: zone,
            otherSlots: otherSlots,
            mapHalfExtentM: mapHalfExtentM
        ) {
            return Result(anchor: best, adjustedFromDrop: !anchorsMatch(best, target))
        }

        if let repelled = repulsionResolvedAnchor(
            seed: target,
            squad: squad,
            squadIndex: squadIndex,
            phase: phase,
            zone: zone,
            otherSlots: otherSlots,
            mapHalfExtentM: mapHalfExtentM
        ) {
            return Result(anchor: repelled, adjustedFromDrop: !anchorsMatch(repelled, target))
        }

        let fallback = sorted.first ?? .defaultForSquadIndex(squadIndex, in: zone)
        return Result(anchor: fallback, adjustedFromDrop: !anchorsMatch(fallback, target))
    }

    // MARK: - Private

    private static func peerSlots(
        squads: [TrainingLabSquad],
        excludingSquadID: UUID,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zones: WorldBuilderZonesSnapshot
    ) -> [TrainingLabFormationSlotGeometry.Slot] {
        let zone = phase == .start ? zones.start : zones.end
        guard zone.placed else { return [] }
        var out: [TrainingLabFormationSlotGeometry.Slot] = []
        for (index, peer) in squads.enumerated() where peer.id != excludingSquadID {
            let anchor = resolvedAnchor(peer: peer, squadIndex: index, phase: phase, zone: zone)
            let layout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: peer,
                squadIndex: index,
                phase: phase,
                anchor: anchor
            )
            out.append(contentsOf: layout.slots)
        }
        return out
    }

    private static func resolvedAnchor(
        peer: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zone: WorldBuilderZoneState
    ) -> TrainingLabZoneFormationAnchor {
        switch phase {
        case .start:
            return peer.startZoneAnchor ?? .defaultForSquadIndex(squadIndex, in: zone)
        case .end:
            return peer.endZoneAnchor ?? .defaultForSquadIndex(squadIndex, in: zone)
        }
    }

    private static func firstValidAnchor(
        candidates: [TrainingLabZoneFormationAnchor],
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zone: WorldBuilderZoneState,
        otherSlots: [TrainingLabFormationSlotGeometry.Slot],
        mapHalfExtentM: Double
    ) -> TrainingLabZoneFormationAnchor? {
        for var candidate in candidates {
            candidate = normalized(candidate)
            let layout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: phase,
                anchor: candidate
            )
            var anchor = layout.anchor
            TrainingLabFormationSlotGeometry.clampAnchorFromMapDrag(
                &anchor,
                circleRadiusM: layout.circleRadiusM,
                zone: zone,
                mapHalfExtentM: mapHalfExtentM
            )
            let committed = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: phase,
                anchor: anchor
            )
            if layoutIsValid(committed, zone: zone, otherSlots: otherSlots) {
                return anchor
            }
        }
        return nil
    }

    private static func layoutIsValid(
        _ layout: TrainingLabFormationSlotGeometry.GroupLayout,
        zone: WorldBuilderZoneState,
        otherSlots: [TrainingLabFormationSlotGeometry.Slot]
    ) -> Bool {
        guard TrainingLabFormationSlotGeometry.groupFitsZoneFromSlots(layout.slots, zone: zone) else {
            return false
        }
        for slot in layout.slots {
            for other in otherSlots where TrainingLabFormationSlotGeometry.slotsOverlap(slot, other) {
                return false
            }
        }
        return true
    }

    private static func repulsionResolvedAnchor(
        seed: TrainingLabZoneFormationAnchor,
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zone: WorldBuilderZoneState,
        otherSlots: [TrainingLabFormationSlotGeometry.Slot],
        mapHalfExtentM: Double
    ) -> TrainingLabZoneFormationAnchor? {
        var candidate = seed
        for _ in 0..<repulsionIterations {
            let layout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: phase,
                anchor: candidate
            )
            var anchor = layout.anchor
            TrainingLabFormationSlotGeometry.clampAnchorFromMapDrag(
                &anchor,
                circleRadiusM: layout.circleRadiusM,
                zone: zone,
                mapHalfExtentM: mapHalfExtentM
            )
            let committed = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: phase,
                anchor: anchor
            )
            if layoutIsValid(committed, zone: zone, otherSlots: otherSlots) {
                return anchor
            }
            guard let nudge = overlapRepulsionNudge(layout: committed, otherSlots: otherSlots) else { break }
            candidate = TrainingLabZoneFormationAnchor(
                centerXM: anchor.centerXM + nudge.dx,
                centerYM: anchor.centerYM + nudge.dy,
                headingDeg: anchor.headingDeg
            )
        }
        return nil
    }

    private static func overlapRepulsionNudge(
        layout: TrainingLabFormationSlotGeometry.GroupLayout,
        otherSlots: [TrainingLabFormationSlotGeometry.Slot]
    ) -> (dx: Double, dy: Double)? {
        var sumDX = 0.0
        var sumDY = 0.0
        var count = 0
        for slot in layout.slots {
            for other in otherSlots where TrainingLabFormationSlotGeometry.slotsOverlap(slot, other) {
                var vx = slot.centerXM - other.centerXM
                var vy = slot.centerYM - other.centerYM
                var dist = (vx * vx + vy * vy).squareRoot()
                if dist < 1e-6 {
                    vx = 1
                    vy = 0
                    dist = 1
                } else {
                    vx /= dist
                    vy /= dist
                }
                let push = TrainingLabFormationSlotGeometry.slotOverlapSeparationM + 0.35
                sumDX += vx * push
                sumDY += vy * push
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let n = Double(count)
        return (sumDX / n, sumDY / n)
    }

    private static func spiralOffsets(
        around origin: TrainingLabZoneFormationAnchor,
        stepM: Double,
        maxRadiusM: Double
    ) -> [TrainingLabZoneFormationAnchor] {
        var out: [TrainingLabZoneFormationAnchor] = []
        var ring = 1
        while Double(ring) * stepM <= maxRadiusM {
            let d = Double(ring) * stepM
            var angle = 0.0
            while angle < 360.0 {
                let rad = angle * .pi / 180
                out.append(
                    TrainingLabZoneFormationAnchor(
                        centerXM: origin.centerXM + d * sin(rad),
                        centerYM: origin.centerYM + d * cos(rad),
                        headingDeg: origin.headingDeg
                    )
                )
                angle += 22.5
            }
            ring += 1
        }
        return out
    }

    private static func anchorDistanceSquared(
        _ a: TrainingLabZoneFormationAnchor,
        _ b: TrainingLabZoneFormationAnchor
    ) -> Double {
        let dx = a.centerXM - b.centerXM
        let dy = a.centerYM - b.centerYM
        return dx * dx + dy * dy
    }

    private static func anchorsMatch(
        _ a: TrainingLabZoneFormationAnchor,
        _ b: TrainingLabZoneFormationAnchor
    ) -> Bool {
        anchorDistanceSquared(a, b) <= anchorMatchEpsilonM * anchorMatchEpsilonM
    }

    private static func normalized(_ anchor: TrainingLabZoneFormationAnchor) -> TrainingLabZoneFormationAnchor {
        var h = anchor.headingDeg.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return TrainingLabZoneFormationAnchor(
            centerXM: anchor.centerXM,
            centerYM: anchor.centerYM,
            headingDeg: h
        )
    }
}
