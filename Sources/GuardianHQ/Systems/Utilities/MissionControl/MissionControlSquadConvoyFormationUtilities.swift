import Foundation

/// Convoy offset geometry: wingmen astern on the **task path** when possible (v1 convoy).
enum MissionControlSquadConvoyFormationUtilities {

    /// Approximate metres per degree latitude (WGS84).
    static let metresPerDegreeLatitude: Double = 111_320

    struct PathVertex: Equatable, Sendable {
        let coord: RouteCoordinate
        /// Cumulative horizontal distance from the first waypoint (metres).
        let alongTrackM: Double
    }

    struct PathProjection: Equatable, Sendable {
        let alongTrackM: Double
        let headingDeg: Double
        let lateralM: Double
    }

    // MARK: - Public convoy targets

    struct ConvoySlot: Equatable, Sendable {
        let coordinate: RouteCoordinate
        /// Convoy axis for pursuit / yaw — path tangent when polyline-anchored, else primary heading.
        let convoyHeadingDeg: Double
        let usesPathPolyline: Bool
    }

    /// True when the primary is on the task polyline within lateral tolerance (mission follow — no “past WP1” gate).
    static func shouldAnchorConvoyToTaskPathDuringMissionFollow(
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        maxLateralM: Double = MissionSquadConvoyFollowControlPolicy.pathAnchorMaxLateralM
    ) -> Bool {
        guard task.waypoints.count >= 2 else { return false }
        let polyline = pathPolyline(waypoints: task.waypoints)
        guard polyline.count >= 2,
              let projection = projectOntoPolyline(
                  latitudeDeg: primaryLatitudeDeg,
                  longitudeDeg: primaryLongitudeDeg,
                  polyline: polyline
              )
        else { return false }
        return projection.lateralM <= maxLateralM
    }

    /// True when wingmen should use polyline slots (primary on path **and** at/ past the first route waypoint).
    static func shouldAnchorConvoyToTaskPath(
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryMissionProgressCurrent: Int32? = nil,
        maxLateralM: Double = MissionSquadConvoyFollowControlPolicy.pathAnchorMaxLateralM,
        allowPathPolylineAnchor: Bool = true
    ) -> Bool {
        guard allowPathPolylineAnchor else { return false }
        guard task.waypoints.count >= 2 else { return false }
        let polyline = pathPolyline(waypoints: task.waypoints)
        guard polyline.count >= 2,
              let projection = projectOntoPolyline(
                  latitudeDeg: primaryLatitudeDeg,
                  longitudeDeg: primaryLongitudeDeg,
                  polyline: polyline
              )
        else { return false }
        guard projection.lateralM <= maxLateralM else { return false }
        if let progress = primaryMissionProgressCurrent, progress >= 1 {
            return true
        }
        let firstLegEndM = polyline[1].alongTrackM
        return projection.alongTrackM
            >= firstLegEndM - MissionSquadConvoyFollowControlPolicy.pathAnchorFirstWaypointAlongToleranceM
    }

    /// Legacy lateral-only probe (prefer ``shouldAnchorConvoyToTaskPath``).
    static func usesTaskPathAnchoredConvoy(
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        maxLateralM: Double = MissionSquadConvoyFollowControlPolicy.pathAnchorMaxLateralM
    ) -> Bool {
        shouldAnchorConvoyToTaskPath(
            task: task,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryMissionProgressCurrent: nil,
            maxLateralM: maxLateralM
        )
    }

    /// Convoy slot on a **Guardian Router** launch→WP1 polyline: project primary along the route, wingmen astern on the spine.
    static func desiredConvoySlotOnLaunchApproachRoute(
        formation: MissionSquadFormationKind = .staggeredConvoy,
        route: [RouteCoordinate],
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing,
        maxLateralM: Double = MissionSquadConvoyFollowControlPolicy.launchApproachPathAnchorMaxLateralM
    ) -> ConvoySlot? {
        let polyline = pathPolyline(route: route)
        guard polyline.count >= 2,
              let projection = projectOntoPolyline(
                  latitudeDeg: primaryLatitudeDeg,
                  longitudeDeg: primaryLongitudeDeg,
                  polyline: polyline
              ),
              projection.lateralM <= maxLateralM
        else { return nil }

        let behindM = Double(wingmanOrdinal + 1) * spacing.alongTrackMetersPerOrdinal
        let targetAlong = max(0, projection.alongTrackM - behindM)
        guard let target = coordinateAtAlongTrack(targetAlong, polyline: polyline) else { return nil }

        let rightM = MissionSquadFormationGeometry.lateralBodyMeters(
            formation: formation,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
        let coordinate = offsetCoordinate(
            latitudeDeg: target.coord.lat,
            longitudeDeg: target.coord.lon,
            headingDeg: target.headingDeg,
            forwardMeters: 0,
            rightMeters: rightM
        )
        let pathHeading = coordinateAtAlongTrack(targetAlong, polyline: polyline)?.headingDeg
            ?? projection.headingDeg
        return ConvoySlot(
            coordinate: coordinate,
            convoyHeadingDeg: pathHeading,
            usesPathPolyline: true
        )
    }

    /// Wingman slot for the selected formation (convoy / chevron / arrowhead).
    static func desiredFormationSlot(
        formation: MissionSquadFormationKind,
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        primaryMissionProgressCurrent: Int32?,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing,
        allowPathPolylineAnchor: Bool = true
    ) -> ConvoySlot {
        desiredConvoySlot(
            formation: formation,
            task: task,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryHeadingDeg: primaryHeadingDeg,
            primaryMissionProgressCurrent: primaryMissionProgressCurrent,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing,
            allowPathPolylineAnchor: allowPathPolylineAnchor
        )
    }

    /// Convoy slot: path polyline astern once the primary is on the first leg; heading-astern before that.
    static func desiredConvoySlot(
        formation: MissionSquadFormationKind = .convoy,
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        primaryMissionProgressCurrent: Int32?,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing,
        allowPathPolylineAnchor: Bool = true
    ) -> ConvoySlot {
        let polyline = pathPolyline(waypoints: task.waypoints)
        if shouldAnchorConvoyToTaskPath(
            task: task,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryMissionProgressCurrent: primaryMissionProgressCurrent,
            allowPathPolylineAnchor: allowPathPolylineAnchor
        ),
           let projection = projectOntoPolyline(
               latitudeDeg: primaryLatitudeDeg,
               longitudeDeg: primaryLongitudeDeg,
               polyline: polyline
           ),
           let onPath = desiredCoordinateOnTaskPath(
               formation: formation,
               waypoints: task.waypoints,
               primaryLatitudeDeg: primaryLatitudeDeg,
               primaryLongitudeDeg: primaryLongitudeDeg,
               wingmanOrdinal: wingmanOrdinal,
               spacing: spacing
           ) {
            let behindM = pathBehindMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing)
            let targetAlong = max(0, projection.alongTrackM - behindM)
            let pathHeading = coordinateAtAlongTrack(targetAlong, polyline: polyline)?.headingDeg
                ?? projection.headingDeg
            return ConvoySlot(
                coordinate: onPath,
                convoyHeadingDeg: pathHeading,
                usesPathPolyline: true
            )
        }
        if allowPathPolylineAnchor,
           shouldAnchorConvoyToTaskPathDuringMissionFollow(
               task: task,
               primaryLatitudeDeg: primaryLatitudeDeg,
               primaryLongitudeDeg: primaryLongitudeDeg
           ),
           let projection = projectOntoPolyline(
               latitudeDeg: primaryLatitudeDeg,
               longitudeDeg: primaryLongitudeDeg,
               polyline: polyline
           ),
           let onPath = desiredCoordinateOnTaskPath(
               formation: formation,
               waypoints: task.waypoints,
               primaryLatitudeDeg: primaryLatitudeDeg,
               primaryLongitudeDeg: primaryLongitudeDeg,
               wingmanOrdinal: wingmanOrdinal,
               spacing: spacing
           ) {
            let behindM = pathBehindMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing)
            let targetAlong = max(0, projection.alongTrackM - behindM)
            let pathHeading = coordinateAtAlongTrack(targetAlong, polyline: polyline)?.headingDeg
                ?? projection.headingDeg
            return ConvoySlot(
                coordinate: onPath,
                convoyHeadingDeg: pathHeading,
                usesPathPolyline: true
            )
        }
        let body = desiredFormationCoordinate(
            formation: formation,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryHeadingDeg: primaryHeadingDeg,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
        return ConvoySlot(
            coordinate: body,
            convoyHeadingDeg: primaryHeadingDeg,
            usesPathPolyline: false
        )
    }

    /// Preferred convoy point (coordinate only — use ``desiredConvoySlot`` when heading / path mode matter).
    static func desiredConvoyCoordinate(
        task: MissionTask,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        primaryMissionProgressCurrent: Int32?,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> RouteCoordinate {
        desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryHeadingDeg: primaryHeadingDeg,
            primaryMissionProgressCurrent: primaryMissionProgressCurrent,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        ).coordinate
    }

    /// Signed along-convoy error (m): positive = wingman ahead of slot toward primary; negative = behind slot.
    static func convoyAlongTrackErrorM(
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double,
        slotCoordinate: RouteCoordinate,
        convoyHeadingDeg: Double
    ) -> Double {
        let h = convoyHeadingDeg * .pi / 180
        let sinH = sin(h)
        let cosH = cos(h)
        let latRad = slotCoordinate.lat * .pi / 180
        let mPerLon = metresPerDegreeLatitude * max(0.01, cos(latRad))
        let northM = (wingmanLatitudeDeg - slotCoordinate.lat) * metresPerDegreeLatitude
        let eastM = (wingmanLongitudeDeg - slotCoordinate.lon) * mPerLon
        return northM * cosH + eastM * sinH
    }

    /// Lateral offset from the convoy axis (m, absolute).
    static func convoyLateralErrorM(
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double,
        slotCoordinate: RouteCoordinate,
        convoyHeadingDeg: Double
    ) -> Double {
        abs(
            convoySignedLateralErrorM(
                wingmanLatitudeDeg: wingmanLatitudeDeg,
                wingmanLongitudeDeg: wingmanLongitudeDeg,
                slotCoordinate: slotCoordinate,
                convoyHeadingDeg: convoyHeadingDeg
            )
        )
    }

    /// Signed lateral offset (m): positive = starboard of convoy axis.
    static func convoySignedLateralErrorM(
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double,
        slotCoordinate: RouteCoordinate,
        convoyHeadingDeg: Double
    ) -> Double {
        let h = convoyHeadingDeg * .pi / 180
        let sinH = sin(h)
        let cosH = cos(h)
        let latRad = slotCoordinate.lat * .pi / 180
        let mPerLon = metresPerDegreeLatitude * max(0.01, cos(latRad))
        let northM = (wingmanLatitudeDeg - slotCoordinate.lat) * metresPerDegreeLatitude
        let eastM = (wingmanLongitudeDeg - slotCoordinate.lon) * mPerLon
        return -northM * sinH + eastM * cosH
    }

    /// Body-forward pursuit speed (m/s, signed) from primary cruise and convoy gap.
    static func pursuitForwardSpeedMS(
        alongErrorM: Double,
        distToSlotM: Double,
        primarySpeedMS: Double?
    ) -> Double {
        if alongErrorM >= MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM {
            let reverse = min(
                MissionSquadConvoyFollowControlPolicy.pursuitMaxReverseMS,
                (alongErrorM - MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM) * 0.35
            )
            return -reverse
        }
        let base = max(primarySpeedMS ?? MissionSquadConvoyFollowControlPolicy.pursuitDefaultCruiseMS,
                       MissionSquadConvoyFollowControlPolicy.pursuitMinForwardMS)
        var speed = base - MissionSquadConvoyFollowControlPolicy.pursuitAlongGain * alongErrorM
        if distToSlotM >= MissionSquadConvoyFollowControlPolicy.pursuitCatchUpDistanceM {
            speed = max(speed, base + MissionSquadConvoyFollowControlPolicy.pursuitMaxBoostAbovePrimaryMS * 0.65)
        }
        let maxForward = base + MissionSquadConvoyFollowControlPolicy.pursuitMaxBoostAbovePrimaryMS
        let minForward = max(
            MissionSquadConvoyFollowControlPolicy.pursuitMinForwardMS,
            base - MissionSquadConvoyFollowControlPolicy.pursuitMaxSlowBelowPrimaryMS
        )
        return min(max(speed, minForward), maxForward)
    }

    /// Signed heading error (deg): positive = wingman should turn clockwise to match target.
    static func headingErrorDeg(
        wingmanHeadingDeg: Double?,
        targetHeadingDeg: Double
    ) -> Double? {
        MissionSquadFormationHeadingPolicy.headingErrorDeg(
            wingmanHeadingDeg: wingmanHeadingDeg,
            targetHeadingDeg: targetHeadingDeg
        )
    }

    /// Yaw rate (deg/s) to match formation target heading (primary by default) while closing lateral error.
    static func pursuitYawRateDegS(
        wingmanHeadingDeg: Double?,
        convoyHeadingDeg: Double,
        lateralErrorM: Double
    ) -> Double {
        let delta = headingErrorDeg(wingmanHeadingDeg: wingmanHeadingDeg, targetHeadingDeg: convoyHeadingDeg) ?? 0
        var rate = headingAlignYawRateDegS(headingErrorDeg: delta)
        // Small lateral offset: nudge yaw with heading correction. Large offset: steer toward slot bearing
        // so GPS course heading does not fight a large heading-error turn during forward pursuit.
        if lateralErrorM > 0.35, abs(delta) < 45 {
            let fromLateral = lateralErrorM * MissionSquadConvoyFollowControlPolicy.pursuitYawRateGainDegSPerM
            rate += (delta >= 0 ? fromLateral : -fromLateral) * 0.65
        }
        return clampYawRateDegS(rate)
    }

    /// Yaw rate from heading error alone (in-place / slot hold).
    static func headingAlignYawRateDegS(headingErrorDeg: Double) -> Double {
        guard abs(headingErrorDeg) > MissionSquadConvoyFollowControlPolicy.pursuitHeadingAlignStartDeg else {
            return 0
        }
        let rate = headingErrorDeg * MissionSquadConvoyFollowControlPolicy.pursuitHeadingAlignGainDegSPerDeg
        return clampYawRateDegS(rate)
    }

    private static func clampYawRateDegS(_ rate: Double) -> Double {
        min(
            MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS,
            max(-MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS, rate)
        )
    }

    /// Forward speed (m/s) for slot approach; zero when in the slot band so heading can align without creep.
    static func pursuitForwardSpeedMS(
        alongErrorM: Double,
        distToSlotM: Double,
        primarySpeedMS: Double?,
        headingErrorDeg: Double? = nil
    ) -> Double {
        if distToSlotM <= MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM,
           let headingErrorDeg,
           abs(headingErrorDeg) > MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg {
            return 0
        }
        return pursuitForwardSpeedMS(
            alongErrorM: alongErrorM,
            distToSlotM: distToSlotM,
            primarySpeedMS: primarySpeedMS
        )
    }

    /// OFFBOARD / Guided pursuit: position carrot (PX4 rover) with gap-aware leash; pair with ``pursuitForwardSpeedMS`` for velocity stacks.
    static func streamedConvoySetpointCoordinate(
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double,
        slotCoordinate: RouteCoordinate,
        convoyHeadingDeg: Double,
        alongErrorM: Double? = nil,
        snapWithinM: Double = MissionSquadConvoyFollowControlPolicy.pursuitSnapArrivalM,
        directSlotBeyondM: Double = MissionSquadConvoyFollowControlPolicy.directSlotBeyondM,
        leashMinM: Double = MissionSquadConvoyFollowControlPolicy.pursuitLeashMinM,
        leashMaxM: Double = MissionSquadConvoyFollowControlPolicy.pursuitLeashMaxM,
        leashCatchUpMaxM: Double = MissionSquadConvoyFollowControlPolicy.pursuitLeashCatchUpMaxM
    ) -> RouteCoordinate {
        let dist = MissionTelemetryGeo.horizontalDistanceM(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: slotCoordinate.lat,
            lon2: slotCoordinate.lon
        )
        if dist <= snapWithinM {
            return slotCoordinate
        }
        let bearing = MissionTelemetryGeo.bearingDegrees(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: slotCoordinate.lat,
            lon2: slotCoordinate.lon
        )
        let along = alongErrorM ?? convoyAlongTrackErrorM(
            wingmanLatitudeDeg: wingmanLatitudeDeg,
            wingmanLongitudeDeg: wingmanLongitudeDeg,
            slotCoordinate: slotCoordinate,
            convoyHeadingDeg: convoyHeadingDeg
        )
        if along < -0.75 {
            let dynamicMax = min(
                leashCatchUpMaxM,
                max(leashMaxM, leashMinM + min(dist * 0.45, leashCatchUpMaxM - leashMinM))
            )
            let leash = min(dist, dynamicMax)
            return offsetCoordinate(
                latitudeDeg: wingmanLatitudeDeg,
                longitudeDeg: wingmanLongitudeDeg,
                headingDeg: bearing,
                forwardMeters: leash,
                rightMeters: 0
            )
        }
        if dist >= directSlotBeyondM, along >= 0 {
            return slotCoordinate
        }
        let leash = min(dist, max(leashMinM, leashMaxM))
        return offsetCoordinate(
            latitudeDeg: wingmanLatitudeDeg,
            longitudeDeg: wingmanLongitudeDeg,
            headingDeg: bearing,
            forwardMeters: leash,
            rightMeters: 0
        )
    }

    /// Wingman position on the mission path at `primaryAlongTrack - spacing`, with optional lane offset.
    static func desiredCoordinateOnTaskPath(
        formation: MissionSquadFormationKind = .convoy,
        waypoints: [RouteWaypoint],
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> RouteCoordinate? {
        let polyline = pathPolyline(waypoints: waypoints)
        guard polyline.count >= 2,
              let projection = projectOntoPolyline(
                  latitudeDeg: primaryLatitudeDeg,
                  longitudeDeg: primaryLongitudeDeg,
                  polyline: polyline
              )
        else { return nil }

        let behindM = pathBehindMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing)
        let targetAlong = max(0, projection.alongTrackM - behindM)
        guard let target = coordinateAtAlongTrack(targetAlong, polyline: polyline) else { return nil }

        let rightM = MissionSquadFormationGeometry.lateralBodyMeters(
            formation: formation,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
        return offsetCoordinate(
            latitudeDeg: target.coord.lat,
            longitudeDeg: target.coord.lon,
            headingDeg: target.headingDeg,
            forwardMeters: 0,
            rightMeters: rightM
        )
    }

    /// Body-frame offset from the primary (pad assembly / off-route follow).
    static func desiredFormationCoordinate(
        formation: MissionSquadFormationKind,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> RouteCoordinate {
        MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: formation,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryHeadingDeg: primaryHeadingDeg,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
    }

    /// Body-frame astern offset from the primary (convoy — legacy name).
    static func desiredCoordinate(
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> RouteCoordinate {
        desiredFormationCoordinate(
            formation: .convoy,
            primaryLatitudeDeg: primaryLatitudeDeg,
            primaryLongitudeDeg: primaryLongitudeDeg,
            primaryHeadingDeg: primaryHeadingDeg,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
    }

    private static func pathBehindMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        MissionSquadFormationGeometry.pathBehindMeters(
            formation: formation,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
    }

    // MARK: - Path geometry

    static func pathPolyline(waypoints: [RouteWaypoint]) -> [PathVertex] {
        pathPolyline(route: waypoints.map(\.coord))
    }

    static func pathPolyline(route: [RouteCoordinate]) -> [PathVertex] {
        guard let first = route.first else { return [] }
        var out: [PathVertex] = [PathVertex(coord: first, alongTrackM: 0)]
        var cumulative = 0.0
        for index in 1..<route.count {
            let prev = route[index - 1]
            let next = route[index]
            cumulative += MissionTelemetryGeo.horizontalDistanceM(
                lat1: prev.lat,
                lon1: prev.lon,
                lat2: next.lat,
                lon2: next.lon
            )
            out.append(PathVertex(coord: next, alongTrackM: cumulative))
        }
        return out
    }

    static func projectOntoPolyline(
        latitudeDeg: Double,
        longitudeDeg: Double,
        polyline: [PathVertex]
    ) -> PathProjection? {
        guard polyline.count >= 2 else { return nil }
        var bestLateral = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        var bestHeading = 0.0

        for index in 1..<polyline.count {
            let start = polyline[index - 1]
            let end = polyline[index]
            let segmentM = end.alongTrackM - start.alongTrackM
            guard segmentM > 0.01 else { continue }

            let distanceAP = MissionTelemetryGeo.horizontalDistanceM(
                lat1: start.coord.lat,
                lon1: start.coord.lon,
                lat2: latitudeDeg,
                lon2: longitudeDeg
            )
            let bearingAP = MissionTelemetryGeo.bearingDegrees(
                lat1: start.coord.lat,
                lon1: start.coord.lon,
                lat2: latitudeDeg,
                lon2: longitudeDeg
            )
            let bearingAB = MissionTelemetryGeo.bearingDegrees(
                lat1: start.coord.lat,
                lon1: start.coord.lon,
                lat2: end.coord.lat,
                lon2: end.coord.lon
            )
            let deltaRad = MissionTelemetryGeo.angleDifferenceDeg(bearingAP, bearingAB) * .pi / 180
            let alongSegment = max(0, min(segmentM, distanceAP * cos(deltaRad)))
            let lateral = abs(distanceAP * sin(deltaRad))
            if lateral < bestLateral {
                bestLateral = lateral
                bestAlong = start.alongTrackM + alongSegment
                bestHeading = bearingAB
            }
        }
        return PathProjection(alongTrackM: bestAlong, headingDeg: bestHeading, lateralM: bestLateral)
    }

    static func coordinateAtAlongTrack(
        _ alongTrackM: Double,
        polyline: [PathVertex]
    ) -> (coord: RouteCoordinate, headingDeg: Double)? {
        guard let last = polyline.last else { return nil }
        let clamped = max(0, min(alongTrackM, last.alongTrackM))
        if clamped <= 0, let first = polyline.first {
            let heading = polyline.count > 1
                ? MissionTelemetryGeo.bearingDegrees(
                    lat1: first.coord.lat,
                    lon1: first.coord.lon,
                    lat2: polyline[1].coord.lat,
                    lon2: polyline[1].coord.lon
                )
                : 0
            return (first.coord, heading)
        }
        for index in 1..<polyline.count {
            let end = polyline[index]
            guard end.alongTrackM >= clamped else { continue }
            let start = polyline[index - 1]
            let segmentM = end.alongTrackM - start.alongTrackM
            let fraction = segmentM > 0.01 ? (clamped - start.alongTrackM) / segmentM : 0
            let lat = start.coord.lat + fraction * (end.coord.lat - start.coord.lat)
            let lon = start.coord.lon + fraction * (end.coord.lon - start.coord.lon)
            let heading = MissionTelemetryGeo.bearingDegrees(
                lat1: start.coord.lat,
                lon1: start.coord.lon,
                lat2: end.coord.lat,
                lon2: end.coord.lon
            )
            return (RouteCoordinate(lat: lat, lon: lon), heading)
        }
        let heading = polyline.count >= 2
            ? MissionTelemetryGeo.bearingDegrees(
                lat1: polyline[polyline.count - 2].coord.lat,
                lon1: polyline[polyline.count - 2].coord.lon,
                lat2: last.coord.lat,
                lon2: last.coord.lon
            )
            : 0
        return (last.coord, heading)
    }

    /// Offset in local forward / right frame (forward = along heading, right = starboard).
    static func offsetCoordinate(
        latitudeDeg: Double,
        longitudeDeg: Double,
        headingDeg: Double,
        forwardMeters: Double,
        rightMeters: Double
    ) -> RouteCoordinate {
        MissionSquadFormationGeometry.offsetCoordinate(
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            headingDeg: headingDeg,
            forwardMeters: forwardMeters,
            rightMeters: rightMeters
        )
    }
}
