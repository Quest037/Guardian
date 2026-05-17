import Foundation

/// Formation playground follow status + operator-facing log lines.
enum FormationsPlaygroundFollowDiagnostics {
    static let stuckTickThreshold = 25
    static let progressEpsilonM = 0.4

    struct Evaluation: Equatable, Sendable {
        let state: FormationsPlaygroundFollowState
        let message: String
        let distanceToSlotM: Double?
        let headingErrorDeg: Double?
        let targetHeadingDeg: Double?
        let headingAligned: Bool
        let coordinateLine: String?
    }

    static func evaluate(
        vehicleLabel: String,
        hub: FleetHubVehicleTelemetry?,
        slot: RouteCoordinate,
        targetHeadingDeg: Double,
        arrivalM: Double,
        stuckDistanceM: Double,
        ticksWithoutProgress: Int,
        headingToleranceDeg: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg
    ) -> Evaluation {
        guard let hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else {
            return Evaluation(
                state: .noTelemetry,
                message: "\(vehicleLabel): waiting for live position.",
                distanceToSlotM: nil,
                headingErrorDeg: nil,
                targetHeadingDeg: targetHeadingDeg,
                headingAligned: false,
                coordinateLine: nil
            )
        }

        let wingmanHeading = MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub)
        let headingError = MissionSquadFormationHeadingPolicy.headingErrorDeg(
            hub: hub,
            targetHeadingDeg: targetHeadingDeg
        )
        let headingAligned = MissionSquadFormationHeadingPolicy.isHeadingAligned(
            hub: hub,
            targetHeadingDeg: targetHeadingDeg,
            toleranceDeg: headingToleranceDeg
        )

        let distM = MissionRunSquadConvoyAssemblyUtilities.distanceToSlotM(
            wingmanLatitudeDeg: lat,
            wingmanLongitudeDeg: lon,
            slot: slot
        )
        let coordLine = String(format: "at %.6f, %.6f", lat, lon)
        let slotLine = String(format: "slot %.6f, %.6f", slot.lat, slot.lon)
        let headingLine = formatHeadingStatus(
            targetHeadingDeg: targetHeadingDeg,
            wingmanHeadingDeg: wingmanHeading,
            headingErrorDeg: headingError,
            aligned: headingAligned,
            toleranceDeg: headingToleranceDeg
        )

        let positionOk = distM <= arrivalM

        if positionOk, headingAligned {
            return Evaluation(
                state: .inPosition,
                message:
                    "\(vehicleLabel): I'm in position (\(formatM(distM)) from slot). \(headingLine)",
                distanceToSlotM: distM,
                headingErrorDeg: headingError,
                targetHeadingDeg: targetHeadingDeg,
                headingAligned: true,
                coordinateLine: coordLine
            )
        }

        if positionOk, !headingAligned {
            return Evaluation(
                state: .movingToPosition,
                message:
                    "\(vehicleLabel): I'm in the slot but turning to match primary heading. \(headingLine) \(coordLine)",
                distanceToSlotM: distM,
                headingErrorDeg: headingError,
                targetHeadingDeg: targetHeadingDeg,
                headingAligned: false,
                coordinateLine: coordLine
            )
        }

        if distM >= stuckDistanceM, ticksWithoutProgress >= stuckTickThreshold {
            return Evaluation(
                state: .stuck,
                message:
                    "\(vehicleLabel): I'm stuck — \(formatM(distM)) from slot for \(ticksWithoutProgress) ticks. \(headingLine) \(coordLine); \(slotLine).",
                distanceToSlotM: distM,
                headingErrorDeg: headingError,
                targetHeadingDeg: targetHeadingDeg,
                headingAligned: headingAligned,
                coordinateLine: coordLine
            )
        }

        return Evaluation(
            state: .movingToPosition,
            message:
                "\(vehicleLabel): I'm moving to position (\(formatM(distM)) from slot). \(headingLine) \(coordLine)",
            distanceToSlotM: distM,
            headingErrorDeg: headingError,
            targetHeadingDeg: targetHeadingDeg,
            headingAligned: headingAligned,
            coordinateLine: coordLine
        )
    }

    static func shouldSnapToSlot(distanceM: Double, arrivalM: Double) -> Bool {
        distanceM > max(6.0, arrivalM * 5)
    }

    static func updateProgressTicks(
        previousDistanceM: Double?,
        currentDistanceM: Double,
        previousTicks: Int
    ) -> Int {
        guard let prev = previousDistanceM else { return 0 }
        if currentDistanceM < prev - progressEpsilonM { return 0 }
        return previousTicks + 1
    }

    private static func formatHeadingStatus(
        targetHeadingDeg: Double,
        wingmanHeadingDeg: Double?,
        headingErrorDeg: Double?,
        aligned: Bool,
        toleranceDeg: Double
    ) -> String {
        if aligned {
            return String(format: "Heading aligned with primary (target %.0f°).", targetHeadingDeg)
        }
        if let wing = wingmanHeadingDeg, let err = headingErrorDeg {
            return String(
                format: "Heading %.0f° off primary target %.0f° (mine %.0f°, need within %.0f°).",
                abs(err),
                targetHeadingDeg,
                wing,
                toleranceDeg
            )
        }
        return String(format: "Heading target %.0f° (waiting for yaw telemetry).", targetHeadingDeg)
    }

    private static func formatM(_ value: Double) -> String {
        String(format: "%.1f m", value)
    }
}
