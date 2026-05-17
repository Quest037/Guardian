import Foundation

/// After formation **position** is locked, runs one slow plotted ``GuardianMovementID/threePointReverse`` attempt.
enum GuardianMovementInSlotHeadingPlanner {

    /// Position achieved — heading maneuver may start (not during approach).
    static func hasFormationPositionLocked(_ context: GuardianMovementSlotApproachContext) -> Bool {
        context.distToSlotM <= GuardianMovementThreePointTurnPolicy.formationPositionLockedMaxDistM
            && abs(context.alongErrorM) <= GuardianMovementThreePointTurnPolicy.formationPositionLockedMaxAlongM
            && abs(context.signedLateralErrorM) <= GuardianMovementThreePointTurnPolicy.formationPositionLockedMaxLateralM
    }

    static func shouldStartHeadingManeuver(_ context: GuardianMovementSlotApproachContext) -> Bool {
        guard GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: context.vehicleType) else {
            return false
        }
        guard hasFormationPositionLocked(context) else { return false }
        guard let err = MissionSquadFormationHeadingPolicy.headingErrorDeg(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            targetHeadingDeg: context.targetHeadingDeg
        ) else { return false }
        return abs(err) > GuardianMovementThreePointTurnPolicy.headingManeuverStartErrorDeg
    }

    /// Plans the current leg along the plotted route; updates ``state`` in/out.
    static func plan(
        _ context: GuardianMovementSlotApproachContext,
        state: inout GuardianMovementSlotSequenceState?,
        now: Date = Date()
    ) -> GuardianMovementPursuitPlan? {
        guard GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: context.vehicleType) else {
            state = nil
            return nil
        }

        if let active = state, active.status == .failed {
            return failedHoldPlan(context: context, state: active)
        }

        if MissionSquadFormationHeadingPolicy.isHeadingAligned(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            targetHeadingDeg: context.targetHeadingDeg
        ) {
            state = nil
            return nil
        }

        if state == nil {
            guard shouldStartHeadingManeuver(context) else { return nil }
            let route = GuardianMovementThreePointRoutePlanner.build(
                slot: context.slot,
                startLatitudeDeg: context.wingmanLatitudeDeg,
                startLongitudeDeg: context.wingmanLongitudeDeg,
                startHeadingDeg: context.wingmanHeadingDeg ?? context.targetHeadingDeg,
                targetHeadingDeg: context.targetHeadingDeg
            )
            state = GuardianMovementSlotSequenceState(
                movementID: .threePointReverse,
                status: .running,
                phase: .reverseLeg,
                targetHeadingDeg: context.targetHeadingDeg,
                sequenceStartedAt: now,
                phaseStartedAt: now,
                route: route,
                legWaypointIndex: 0,
                failureReason: nil
            )
        }

        guard var active = state else { return nil }

        if !hasFormationPositionLocked(context), active.status == .running {
            active.status = .failed
            active.failureReason = "position lost before heading maneuver finished"
            state = active
            return failedHoldPlan(context: context, state: active)
        }

        if active.status == .running {
            if let failure = maneuverFailureReason(context: context, state: active, now: now) {
                active.status = .failed
                active.failureReason = failure
                state = active
                return failedHoldPlan(context: context, state: active)
            }
            advanceRunningState(context: context, state: &active, now: now)
            state = active
            if active.status == .succeeded {
                return nil
            }
            if active.status == .failed {
                return failedHoldPlan(context: context, state: active)
            }
            return planLeg(context: context, state: active)
        }

        state = active
        return nil
    }

    // MARK: - State machine

    private static func advanceRunningState(
        context: GuardianMovementSlotApproachContext,
        state: inout GuardianMovementSlotSequenceState,
        now: Date
    ) {
        let legDone = GuardianMovementThreePointRoutePlanner.legComplete(
            phase: state.phase,
            route: state.route,
            waypointIndex: state.legWaypointIndex,
            wingmanLatitudeDeg: context.wingmanLatitudeDeg,
            wingmanLongitudeDeg: context.wingmanLongitudeDeg
        )
        if legDone {
            switch state.phase {
            case .reverseLeg:
                state.phase = .forwardLeg
                state.phaseStartedAt = now
                state.legWaypointIndex = 0
            case .forwardLeg:
                if MissionSquadFormationHeadingPolicy.isHeadingAligned(
                    wingmanHeadingDeg: context.wingmanHeadingDeg,
                    targetHeadingDeg: context.targetHeadingDeg
                ) {
                    state.status = .succeeded
                } else {
                    state.status = .failed
                    state.failureReason = "forward leg complete but heading still off"
                }
            }
            return
        }

        let leg = GuardianMovementThreePointRoutePlanner.waypoints(for: state.phase, route: state.route)
        let target = leg[min(state.legWaypointIndex, leg.count - 1)]
        let dist = MissionTelemetryGeo.horizontalDistanceM(
            lat1: context.wingmanLatitudeDeg,
            lon1: context.wingmanLongitudeDeg,
            lat2: target.lat,
            lon2: target.lon
        )
        if dist <= GuardianMovementThreePointTurnPolicy.waypointArrivalM,
           state.legWaypointIndex + 1 < leg.count {
            state.legWaypointIndex += 1
        }
    }

    private static func maneuverFailureReason(
        context: GuardianMovementSlotApproachContext,
        state: GuardianMovementSlotSequenceState,
        now: Date
    ) -> String? {
        if now.timeIntervalSince(state.sequenceStartedAt) >= GuardianMovementThreePointTurnPolicy.wholeManeuverTimeoutS {
            return "3-point heading maneuver timed out"
        }
        if context.distToSlotM > GuardianMovementThreePointTurnPolicy.abortIfDistFromSlotExceedsM {
            return String(format: "drifted %.1f m from slot during heading maneuver", context.distToSlotM)
        }
        return nil
    }

    // MARK: - Plans

    private static func planLeg(
        context: GuardianMovementSlotApproachContext,
        state: GuardianMovementSlotSequenceState
    ) -> GuardianMovementPursuitPlan {
        let setpoint = GuardianMovementThreePointRoutePlanner.setpoint(
            phase: state.phase,
            route: state.route,
            waypointIndex: state.legWaypointIndex,
            wingmanLatitudeDeg: context.wingmanLatitudeDeg,
            wingmanLongitudeDeg: context.wingmanLongitudeDeg
        )
        let headingErr = MissionSquadFormationHeadingPolicy.headingErrorDeg(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            targetHeadingDeg: context.targetHeadingDeg
        ) ?? 0
        let yaw = legYawRateDegS(headingErrorDeg: headingErr)
        let legLabel = state.phase == .reverseLeg ? "reverse" : "forward"
        let forwardMS: Double
        switch state.phase {
        case .reverseLeg:
            forwardMS = -GuardianMovementThreePointTurnPolicy.reverseLegForwardMS
        case .forwardLeg:
            forwardMS = GuardianMovementThreePointTurnPolicy.forwardLegForwardMS
        }
        return GuardianMovementPursuitPlan(
            movementID: .threePointReverse,
            bodyForwardMS: forwardMS,
            bodyRightMS: 0,
            yawspeedDegS: yaw,
            pursuitSetpoint: setpoint,
            summary: String(
                format: "3-point %@ leg wp %d/%d (heading err %.0f°).",
                legLabel,
                state.legWaypointIndex + 1,
                GuardianMovementThreePointRoutePlanner.waypoints(for: state.phase, route: state.route).count,
                headingErr
            )
        )
    }

    private static func failedHoldPlan(
        context: GuardianMovementSlotApproachContext,
        state: GuardianMovementSlotSequenceState
    ) -> GuardianMovementPursuitPlan {
        let reason = state.failureReason ?? "heading maneuver failed"
        return GuardianMovementPursuitPlan(
            movementID: .threePointReverse,
            bodyForwardMS: 0,
            bodyRightMS: 0,
            yawspeedDegS: 0,
            pursuitSetpoint: RouteCoordinate(
                lat: context.wingmanLatitudeDeg,
                lon: context.wingmanLongitudeDeg
            ),
            sequenceHalted: true,
            summary: "3-point STOPPED — \(reason)."
        )
    }

    private static func legYawRateDegS(headingErrorDeg: Double) -> Double {
        let raw = MissionControlSquadConvoyFormationUtilities.headingAlignYawRateDegS(
            headingErrorDeg: headingErrorDeg
        )
        let scaled = raw * GuardianMovementThreePointTurnPolicy.legYawRateScale
        return min(
            GuardianMovementThreePointTurnPolicy.maxLegYawRateDegS,
            max(-GuardianMovementThreePointTurnPolicy.maxLegYawRateDegS, scaled)
        )
    }
}
