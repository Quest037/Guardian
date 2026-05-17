import Foundation

/// Builds a slow, analysable reverse-then-forward path for in-slot heading alignment on UGV.
enum GuardianMovementThreePointRoutePlanner {

    static func build(
        slot: RouteCoordinate,
        startLatitudeDeg: Double,
        startLongitudeDeg: Double,
        startHeadingDeg: Double,
        targetHeadingDeg: Double
    ) -> GuardianMovementThreePointRoute {
        let headingErr = MissionTelemetryGeo.angleDifferenceDeg(targetHeadingDeg, startHeadingDeg)
        let turnSign = headingErr >= 0 ? 1.0 : -1.0
        let absErr = abs(headingErr)
        let reverseM = min(
            GuardianMovementThreePointTurnPolicy.reverseArcLengthM,
            max(
                GuardianMovementThreePointTurnPolicy.minReverseArcLengthM,
                GuardianMovementThreePointTurnPolicy.minReverseArcLengthM + absErr * 0.012
            )
        )
        let midHeading = normalizeHeadingDeg(
            startHeadingDeg + turnSign * min(absErr * 0.52, GuardianMovementThreePointTurnPolicy.maxMidLegHeadingOffsetDeg)
        )

        let reverseSteps = GuardianMovementThreePointTurnPolicy.routeWaypointCountPerLeg
        var reverse: [RouteCoordinate] = []
        reverse.reserveCapacity(reverseSteps)
        for step in 1...reverseSteps {
            let frac = Double(step) / Double(reverseSteps)
            let backM = reverseM * frac
            reverse.append(
                MissionControlSquadConvoyFormationUtilities.offsetCoordinate(
                    latitudeDeg: startLatitudeDeg,
                    longitudeDeg: startLongitudeDeg,
                    headingDeg: startHeadingDeg,
                    forwardMeters: -backM,
                    rightMeters: 0
                )
            )
            _ = interpolateHeadingDeg(from: startHeadingDeg, to: midHeading, fraction: frac)
        }

        let reverseEnd = reverse.last ?? RouteCoordinate(lat: startLatitudeDeg, lon: startLongitudeDeg)
        var forward: [RouteCoordinate] = []
        forward.reserveCapacity(reverseSteps + 1)
        for step in 1...reverseSteps {
            let frac = Double(step) / Double(reverseSteps)
            let blendedLat = reverseEnd.lat + (slot.lat - reverseEnd.lat) * frac
            let blendedLon = reverseEnd.lon + (slot.lon - reverseEnd.lon) * frac
            forward.append(RouteCoordinate(lat: blendedLat, lon: blendedLon))
        }
        if forward.last != slot {
            forward.append(slot)
        }

        return GuardianMovementThreePointRoute(
            slot: slot,
            targetHeadingDeg: targetHeadingDeg,
            reverseWaypoints: reverse,
            forwardWaypoints: forward
        )
    }

    static func waypoints(for phase: GuardianMovementThreePointPhase, route: GuardianMovementThreePointRoute) -> [RouteCoordinate] {
        switch phase {
        case .reverseLeg: return route.reverseWaypoints
        case .forwardLeg: return route.forwardWaypoints
        }
    }

    static func setpoint(
        phase: GuardianMovementThreePointPhase,
        route: GuardianMovementThreePointRoute,
        waypointIndex: Int,
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double
    ) -> RouteCoordinate {
        let leg = waypoints(for: phase, route: route)
        guard !leg.isEmpty else { return route.slot }
        let index = min(max(0, waypointIndex), leg.count - 1)
        let target = leg[index]
        let dist = MissionTelemetryGeo.horizontalDistanceM(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: target.lat,
            lon2: target.lon
        )
        if dist <= GuardianMovementThreePointTurnPolicy.waypointArrivalM, index + 1 < leg.count {
            return leg[index + 1]
        }
        return target
    }

    static func legComplete(
        phase: GuardianMovementThreePointPhase,
        route: GuardianMovementThreePointRoute,
        waypointIndex: Int,
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double
    ) -> Bool {
        let leg = waypoints(for: phase, route: route)
        guard !leg.isEmpty else { return true }
        let index = min(max(0, waypointIndex), leg.count - 1)
        let target = leg[index]
        let atLast = index >= leg.count - 1
        let dist = MissionTelemetryGeo.horizontalDistanceM(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: target.lat,
            lon2: target.lon
        )
        return atLast && dist <= GuardianMovementThreePointTurnPolicy.waypointArrivalM
    }

    private static func interpolateHeadingDeg(from: Double, to: Double, fraction: Double) -> Double {
        let delta = MissionTelemetryGeo.angleDifferenceDeg(to, from)
        return normalizeHeadingDeg(from + delta * fraction)
    }

    private static func normalizeHeadingDeg(_ heading: Double) -> Double {
        var h = heading.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }
}
