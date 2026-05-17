import Foundation

/// Bridges formation slot geometry + movement planner → ``FormationFollowStream/Target``.
@MainActor
enum GuardianFormationSlotPursuitPlanning {

    struct Result: Equatable, Sendable {
        let coord: RouteCoordinate
        let targetHeadingDeg: Double
        let plan: GuardianMovementPursuitPlan
        let evidence: GuardianMovementEvidenceRecord
    }

    static func plan(
        slot: RouteCoordinate,
        targetHeadingDeg: Double,
        vehicleType: FleetVehicleType,
        hub: FleetHubVehicleTelemetry?,
        primarySpeedMS: Double?,
        wingmanVehicleID: String? = nil,
        sequenceStore: GuardianMovementSequenceStore? = nil,
        directSlotBeyondM: Double = MissionSquadConvoyFollowControlPolicy.directSlotBeyondM,
        alongErrorM: Double? = nil
    ) -> Result? {
        let wLat = hub?.latitudeDeg
        let wLon = hub?.longitudeDeg
        guard let context = GuardianMovementPlanner.makeSlotApproachContext(
            vehicleType: vehicleType,
            wingmanLatitudeDeg: wLat,
            wingmanLongitudeDeg: wLon,
            wingmanHeadingDeg: MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub),
            slot: slot,
            targetHeadingDeg: targetHeadingDeg,
            primarySpeedMS: primarySpeedMS
        ) else { return nil }

        let coord: RouteCoordinate
        if let wLat, let wLon {
            coord = MissionControlSquadConvoyFormationUtilities.streamedConvoySetpointCoordinate(
                wingmanLatitudeDeg: wLat,
                wingmanLongitudeDeg: wLon,
                slotCoordinate: slot,
                convoyHeadingDeg: targetHeadingDeg,
                alongErrorM: alongErrorM ?? context.alongErrorM,
                directSlotBeyondM: directSlotBeyondM
            )
        } else {
            coord = slot
        }

        let (plan, declined) = GuardianMovementPlanner.planSlotApproach(
            context,
            vehicleID: wingmanVehicleID,
            sequenceStore: sequenceStore
        )
        let streamCoord = plan.pursuitSetpoint ?? coord
        let evidence = GuardianMovementEvidenceRecord(
            vehicleType: vehicleType,
            plan: plan,
            context: context,
            declinedMovementIDs: declined
        )
        return Result(
            coord: streamCoord,
            targetHeadingDeg: targetHeadingDeg,
            plan: plan,
            evidence: evidence
        )
    }

    static func applyPlan(
        coord: RouteCoordinate,
        targetHeadingDeg: Double,
        wingmanAbsoluteAltitudeM: Double,
        plan: GuardianMovementPursuitPlan,
        pursuitSpeedScale: Float = 1.0
    ) -> FormationFollowStream.Target {
        let streamCoord = plan.pursuitSetpoint ?? coord
        let useVelocityBody = plan.movementID.prefersVelocityBodyExecution && !plan.sequenceHalted
        // In-slot heading on holonomic stacks: position-global yaw; UGV uses body velocity via catalogue flag above.
        if plan.sequenceHalted {
            return FormationFollowStream.Target(
                coord: streamCoord,
                absoluteAltitudeM: wingmanAbsoluteAltitudeM,
                yawDeg: targetHeadingDeg,
                pursuitForwardMS: nil,
                pursuitYawspeedDegS: nil,
                useVelocityBodyPursuit: false
            )
        }
        if !useVelocityBody, plan.bodyForwardMS == 0, abs(plan.yawspeedDegS) > 0.01 {
            return FormationFollowStream.Target(
                coord: streamCoord,
                absoluteAltitudeM: wingmanAbsoluteAltitudeM,
                yawDeg: targetHeadingDeg,
                pursuitForwardMS: nil,
                pursuitYawspeedDegS: nil,
                useVelocityBodyPursuit: false
            )
        }
        return FormationFollowStream.Target(
            coord: streamCoord,
            absoluteAltitudeM: wingmanAbsoluteAltitudeM,
            yawDeg: targetHeadingDeg,
            pursuitForwardMS: Float(plan.bodyForwardMS) * pursuitSpeedScale,
            pursuitYawspeedDegS: Float(plan.yawspeedDegS) * pursuitSpeedScale,
            useVelocityBodyPursuit: useVelocityBody
        )
    }
}
