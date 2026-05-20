import Foundation

/// End-zone arrival check for Training transit runs (hub telemetry vs resolved end slot).
enum TrainingLabRunEndEvaluator {
    static let defaultArrivalM: Double = TrainingSkillScorer.defaultArrivalM
    static let defaultHeadingToleranceDeg: Double = TrainingSkillScorer.defaultHeadingToleranceDeg

    static func evaluate(
        entryID: UUID,
        vehicleID: String,
        hub: FleetHubVehicleTelemetry?,
        goal: TrainingTaskPose,
        episodeDurationS: Double,
        endSlot: TrainingLabFormationSlotGeometry.Slot,
        mapGeodeticOrigin: SimSpawnDefaults,
        requiresStrictEndSlotBox: Bool
    ) -> TrainingRunVehicleOutcome {
        if requiresStrictEndSlotBox {
            return evaluateStrictEndSlot(
                entryID: entryID,
                vehicleID: vehicleID,
                hub: hub,
                goal: goal,
                episodeDurationS: episodeDurationS,
                endSlot: endSlot,
                mapGeodeticOrigin: mapGeodeticOrigin
            )
        }
        let score = TrainingSkillScorer.evaluate(
            hub: hub,
            goal: goal,
            episodeDurationS: episodeDurationS,
            constraintViolations: []
        )
        return TrainingRunVehicleOutcome(
            entryID: entryID,
            vehicleID: vehicleID,
            positionErrorM: score.positionErrorM,
            headingErrorDeg: score.headingErrorDeg,
            succeeded: score.succeeded,
            insideEndSlotBox: nil,
            detail: score.succeeded
                ? nil
                : String(format: "Position %.1f m, heading %.0f° off.", score.positionErrorM, score.headingErrorDeg)
        )
    }

    /// Explicit end formation: centre inside painted slot box + heading aligned with slot yaw.
    private static func evaluateStrictEndSlot(
        entryID: UUID,
        vehicleID: String,
        hub: FleetHubVehicleTelemetry?,
        goal: TrainingTaskPose,
        episodeDurationS: Double,
        endSlot: TrainingLabFormationSlotGeometry.Slot,
        mapGeodeticOrigin: SimSpawnDefaults
    ) -> TrainingRunVehicleOutcome {
        guard let hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else {
            return TrainingRunVehicleOutcome(
                entryID: entryID,
                vehicleID: vehicleID,
                positionErrorM: .infinity,
                headingErrorDeg: .infinity,
                succeeded: false,
                insideEndSlotBox: false,
                detail: "No telemetry."
            )
        }

        let taskPose = TrainingTaskPose(
            latitudeDeg: lat,
            longitudeDeg: lon,
            headingDeg: goal.headingDeg,
            absoluteAltitudeM: goal.absoluteAltitudeM
        )
        let env = TrainingEnvironmentGeodesy.environmentPose(
            taskPose: taskPose,
            origin: mapGeodeticOrigin
        )
        let insideBox = TrainingLabFormationSlotGeometry.vehicleCenterInsideSlot(
            vehicleXM: env.xM,
            vehicleYM: env.yM,
            slot: endSlot
        )
        let positionErrorM = TrainingLabFormationSlotGeometry.horizontalDistanceToSlotCenterM(
            vehicleXM: env.xM,
            vehicleYM: env.yM,
            slot: endSlot
        )
        let headingErrorDeg = abs(
            MissionSquadFormationHeadingPolicy.headingErrorDeg(
                hub: hub,
                targetHeadingDeg: endSlot.headingDeg
            ) ?? 180
        )
        let headingOk = MissionSquadFormationHeadingPolicy.isHeadingAligned(
            hub: hub,
            targetHeadingDeg: endSlot.headingDeg,
            toleranceDeg: defaultHeadingToleranceDeg
        )
        let succeeded = insideBox && headingOk
        let detail: String? = succeeded
            ? nil
            : strictEndSlotDetail(
                insideBox: insideBox,
                headingOk: headingOk,
                positionErrorM: positionErrorM,
                headingErrorDeg: headingErrorDeg
            )

        return TrainingRunVehicleOutcome(
            entryID: entryID,
            vehicleID: vehicleID,
            positionErrorM: positionErrorM,
            headingErrorDeg: headingErrorDeg,
            succeeded: succeeded,
            insideEndSlotBox: insideBox,
            detail: detail
        )
    }

    private static func strictEndSlotDetail(
        insideBox: Bool,
        headingOk: Bool,
        positionErrorM: Double,
        headingErrorDeg: Double
    ) -> String {
        if !insideBox, !headingOk {
            return String(
                format: "Outside end slot box (%.1f m from centre), heading %.0f° off.",
                positionErrorM,
                headingErrorDeg
            )
        }
        if !insideBox {
            return String(format: "Outside end slot box (%.1f m from centre).", positionErrorM)
        }
        return String(format: "Heading %.0f° off.", headingErrorDeg)
    }

    static func failureCode(
        hub: FleetHubVehicleTelemetry?,
        outcome: TrainingRunVehicleOutcome,
        requiresStrictEndSlotBox: Bool
    ) -> TrainingRunFailureCode {
        guard hub != nil else { return .commsLost }
        if requiresStrictEndSlotBox, outcome.insideEndSlotBox == false {
            return .endFormationMismatch
        }
        if outcome.headingErrorDeg > defaultHeadingToleranceDeg {
            return .endHeadingMiss
        }
        return .endPositionMiss
    }

    static func squadOutcome(
        squadID: UUID,
        vehicleOutcomes: [TrainingRunVehicleOutcome],
        failureCode: TrainingRunFailureCode? = nil,
        operatorMessage: String? = nil
    ) -> TrainingRunSquadOutcome {
        let succeeded = failureCode == nil && vehicleOutcomes.allSatisfy(\.succeeded)
        return TrainingRunSquadOutcome(
            squadID: squadID,
            vehicleOutcomes: vehicleOutcomes,
            succeeded: succeeded,
            failureCode: failureCode,
            operatorMessage: operatorMessage
        )
    }
}
