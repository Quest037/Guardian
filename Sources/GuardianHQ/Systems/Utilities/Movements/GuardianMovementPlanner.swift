import Foundation

/// Selects a catalogue movement and body-frame pursuit rates for formation slot approach.
@MainActor
enum GuardianMovementPlanner {

    static func makeSlotApproachContext(
        vehicleType: FleetVehicleType,
        wingmanLatitudeDeg: Double?,
        wingmanLongitudeDeg: Double?,
        wingmanHeadingDeg: Double?,
        slot: RouteCoordinate,
        targetHeadingDeg: Double,
        primarySpeedMS: Double?
    ) -> GuardianMovementSlotApproachContext? {
        guard let wingmanLatitudeDeg, let wingmanLongitudeDeg else { return nil }
        let along = MissionControlSquadConvoyFormationUtilities.convoyAlongTrackErrorM(
            wingmanLatitudeDeg: wingmanLatitudeDeg,
            wingmanLongitudeDeg: wingmanLongitudeDeg,
            slotCoordinate: slot,
            convoyHeadingDeg: targetHeadingDeg
        )
        let signedLateral = MissionControlSquadConvoyFormationUtilities.convoySignedLateralErrorM(
            wingmanLatitudeDeg: wingmanLatitudeDeg,
            wingmanLongitudeDeg: wingmanLongitudeDeg,
            slotCoordinate: slot,
            convoyHeadingDeg: targetHeadingDeg
        )
        let dist = MissionTelemetryGeo.horizontalDistanceM(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: slot.lat,
            lon2: slot.lon
        )
        return GuardianMovementSlotApproachContext(
            vehicleType: vehicleType,
            wingmanLatitudeDeg: wingmanLatitudeDeg,
            wingmanLongitudeDeg: wingmanLongitudeDeg,
            wingmanHeadingDeg: wingmanHeadingDeg,
            slot: slot,
            convoyHeadingDeg: targetHeadingDeg,
            targetHeadingDeg: targetHeadingDeg,
            alongErrorM: along,
            signedLateralErrorM: signedLateral,
            distToSlotM: dist,
            primarySpeedMS: primarySpeedMS
        )
    }

    static func planSlotApproach(
        _ context: GuardianMovementSlotApproachContext,
        vehicleID: String? = nil,
        sequenceStore: GuardianMovementSequenceStore? = nil,
        now: Date = Date()
    ) -> (plan: GuardianMovementPursuitPlan, declined: [GuardianMovementID]) {
        var declined: [GuardianMovementID] = []

        if let vehicleID, let sequenceStore {
            var sequenceState = sequenceStore.state(for: vehicleID)
            if sequenceState != nil
                || GuardianMovementInSlotHeadingPlanner.hasFormationPositionLocked(context) {
                if let sequencePlan = GuardianMovementInSlotHeadingPlanner.plan(
                    context,
                    state: &sequenceState,
                    now: now
                ) {
                    sequenceStore.setState(sequenceState, for: vehicleID)
                    declined.append(contentsOf: declinedInSlotMovements(context: context, selected: sequencePlan.movementID))
                    return (sequencePlan, declined)
                }
            }
            sequenceStore.setState(sequenceState, for: vehicleID)
        } else {
            var ephemeral: GuardianMovementSlotSequenceState?
            if let sequencePlan = GuardianMovementInSlotHeadingPlanner.plan(context, state: &ephemeral, now: now) {
                declined.append(contentsOf: declinedInSlotMovements(context: context, selected: sequencePlan.movementID))
                return (sequencePlan, declined)
            }
        }

        if shouldReverse(context) {
            if GuardianMovementCapabilities.supports(.reverse, vehicleType: context.vehicleType) {
                return (planReverse(context), declined)
            }
            declined.append(.reverse)
        }

        if GuardianMovementCapabilities.supports(.strafe, vehicleType: context.vehicleType),
           abs(context.signedLateralErrorM) > 2.0,
           abs(context.alongErrorM) < MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM {
            // v1: strafe catalogue entry exists; execution stays forward pursuit until body-right streaming lands.
            declined.append(.strafe)
        } else if !GuardianMovementCapabilities.supports(.strafe, vehicleType: context.vehicleType) {
            declined.append(.strafe)
        }

        if !GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: context.vehicleType) {
            declined.append(.threePointReverse)
        }
        if !GuardianMovementCapabilities.supports(.threePointForward, vehicleType: context.vehicleType) {
            declined.append(.threePointForward)
        }

        return (planForwardPursuit(context), declined)
    }

    static func evidence(
        from context: GuardianMovementSlotApproachContext,
        vehicleID: String? = nil,
        sequenceStore: GuardianMovementSequenceStore? = nil
    ) -> GuardianMovementEvidenceRecord {
        let (plan, declined) = planSlotApproach(
            context,
            vehicleID: vehicleID,
            sequenceStore: sequenceStore
        )
        return GuardianMovementEvidenceRecord(
            vehicleType: context.vehicleType,
            plan: plan,
            context: context,
            declinedMovementIDs: declined
        )
    }

    // MARK: - Selection

    private static func shouldReverse(_ context: GuardianMovementSlotApproachContext) -> Bool {
        context.alongErrorM >= MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM
    }

    private static func declinedInSlotMovements(
        context: GuardianMovementSlotApproachContext,
        selected: GuardianMovementID
    ) -> [GuardianMovementID] {
        var declined: [GuardianMovementID] = []
        for movement in [GuardianMovementID.threePointReverse, .threePointForward, .strafe] where movement != selected {
            if !GuardianMovementCapabilities.supports(movement, vehicleType: context.vehicleType) {
                declined.append(movement)
            }
        }
        if selected != .strafe,
           GuardianMovementCapabilities.supports(.strafe, vehicleType: context.vehicleType),
           abs(context.signedLateralErrorM) > 2.0 {
            declined.append(.strafe)
        }
        return declined
    }

    // MARK: - Executors

    private static func planReverse(_ context: GuardianMovementSlotApproachContext) -> GuardianMovementPursuitPlan {
        let reverseMS = min(
            MissionSquadConvoyFollowControlPolicy.pursuitMaxReverseMS,
            (context.alongErrorM - MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM) * 0.35
        )
        let yaw = reversePursuitYawRateDegS(context: context)
        let steerNote = abs(context.signedLateralErrorM) > 0.4
            ? String(format: " steering %.1f°/s", yaw)
            : ""
        return GuardianMovementPursuitPlan(
            movementID: .reverse,
            bodyForwardMS: -reverseMS,
            bodyRightMS: 0,
            yawspeedDegS: yaw,
            summary: String(
                format: "Reverse %.2f m/s (%.1f m ahead of slot)%@.",
                reverseMS,
                context.alongErrorM,
                steerNote
            )
        )
    }

    private static func planForwardPursuit(_ context: GuardianMovementSlotApproachContext) -> GuardianMovementPursuitPlan {
        let headingErr = MissionSquadFormationHeadingPolicy.headingErrorDeg(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            targetHeadingDeg: context.targetHeadingDeg
        )
        let forward = MissionControlSquadConvoyFormationUtilities.pursuitForwardSpeedMS(
            alongErrorM: context.alongErrorM,
            distToSlotM: context.distToSlotM,
            primarySpeedMS: context.primarySpeedMS,
            headingErrorDeg: headingErr
        )
        var yaw = MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            convoyHeadingDeg: context.targetHeadingDeg,
            lateralErrorM: abs(context.signedLateralErrorM)
        )
        if abs(context.signedLateralErrorM) > 0.35,
           let heading = context.wingmanHeadingDeg,
           let err = headingErr,
           abs(err) >= 45 {
            let bearingToSlot = MissionTelemetryGeo.bearingDegrees(
                lat1: context.wingmanLatitudeDeg,
                lon1: context.wingmanLongitudeDeg,
                lat2: context.slot.lat,
                lon2: context.slot.lon
            )
            let towardSlot = MissionTelemetryGeo.angleDifferenceDeg(bearingToSlot, heading)
            yaw += towardSlot * 0.14
            yaw = min(
                MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS,
                max(-MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS, yaw)
            )
        }
        if GuardianMovementInSlotHeadingPlanner.hasFormationPositionLocked(context),
           GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: context.vehicleType) {
            return GuardianMovementPursuitPlan(
                movementID: .forwardPursuit,
                bodyForwardMS: 0,
                bodyRightMS: 0,
                yawspeedDegS: 0,
                summary: "Formation position locked — heading maneuver handles yaw."
            )
        }

        let inSlotTurn = forward == 0 && abs(yaw) > 0.01
        return GuardianMovementPursuitPlan(
            movementID: .forwardPursuit,
            bodyForwardMS: forward,
            bodyRightMS: 0,
            yawspeedDegS: yaw,
            summary: String(
                format: inSlotTurn
                    ? "Heading align in slot (yaw %.0f°/s, err %.0f°)."
                    : "Forward pursuit %.2f m/s (along err %.1f m, lateral %.1f m).",
                inSlotTurn ? yaw : forward,
                inSlotTurn ? (headingErr ?? 0) : context.alongErrorM,
                inSlotTurn ? 0 : context.signedLateralErrorM
            )
        )
    }

    /// Steered reverse: match formation heading + yaw toward slot bearing + lateral correction while astern.
    static func reversePursuitYawRateDegS(context: GuardianMovementSlotApproachContext) -> Double {
        let lateralAbs = abs(context.signedLateralErrorM)
        var rate = MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
            wingmanHeadingDeg: context.wingmanHeadingDeg,
            convoyHeadingDeg: context.targetHeadingDeg,
            lateralErrorM: lateralAbs
        ) * GuardianMovementReversePolicy.headingAlignScale

        if let heading = context.wingmanHeadingDeg {
            let bearingToSlot = MissionTelemetryGeo.bearingDegrees(
                lat1: context.wingmanLatitudeDeg,
                lon1: context.wingmanLongitudeDeg,
                lat2: context.slot.lat,
                lon2: context.slot.lon
            )
            let towardSlot = MissionTelemetryGeo.angleDifferenceDeg(bearingToSlot, heading)
            rate += towardSlot * GuardianMovementReversePolicy.bearingSteerGainDegSPerDeg
            rate += context.signedLateralErrorM * GuardianMovementReversePolicy.lateralSteerGainDegSPerM
        }

        return min(
            MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS,
            max(-MissionSquadConvoyFollowControlPolicy.pursuitYawRateMaxDegS, rate)
        )
    }
}
