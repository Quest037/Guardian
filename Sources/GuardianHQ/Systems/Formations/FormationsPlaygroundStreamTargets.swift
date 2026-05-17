import Foundation

/// OFFBOARD / GUIDED setpoints for the formation playground (mirrors squad wingman pursuit helpers).
@MainActor
enum FormationsPlaygroundStreamTargets {
    /// Playground convoy closes gaps faster than production squad follow defaults.
    static let pursuitSpeedScale: Float = 2.0

    static func primaryHold(
        lat: Double,
        lon: Double,
        primaryHeadingDeg: Double,
        absoluteAltitudeM: Double
    ) -> FormationFollowStream.Target {
        let yawDeg = MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
            primaryHeadingDeg: primaryHeadingDeg
        )
        return FormationFollowStream.Target(
            coord: RouteCoordinate(lat: lat, lon: lon),
            absoluteAltitudeM: absoluteAltitudeM,
            yawDeg: yawDeg,
            pursuitForwardMS: nil,
            pursuitYawspeedDegS: nil
        )
    }

    static func wingmanPursuit(
        wingmanVehicleID: String,
        slot: RouteCoordinate,
        primaryHeadingDeg: Double,
        vehicleType: FleetVehicleType,
        wingmanAbsoluteAltitudeM: Double,
        primarySpeedMS: Double?,
        fleetLink: FleetLinkService
    ) -> FormationFollowStream.Target {
        let targetHeadingDeg = MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
            primaryHeadingDeg: primaryHeadingDeg
        )
        let hub = fleetLink.hubTelemetry(forVehicleID: wingmanVehicleID)

        guard let pursuit = Utilities.movements.formationSlotPursuit(
            slot: slot,
            targetHeadingDeg: targetHeadingDeg,
            vehicleType: vehicleType,
            hub: hub,
            primarySpeedMS: primarySpeedMS,
            wingmanVehicleID: wingmanVehicleID
        ) else {
            return FormationFollowStream.Target(
                coord: slot,
                absoluteAltitudeM: wingmanAbsoluteAltitudeM,
                yawDeg: targetHeadingDeg,
                pursuitForwardMS: nil,
                pursuitYawspeedDegS: nil
            )
        }

        return GuardianFormationSlotPursuitPlanning.applyPlan(
            coord: pursuit.coord,
            targetHeadingDeg: targetHeadingDeg,
            wingmanAbsoluteAltitudeM: wingmanAbsoluteAltitudeM,
            plan: pursuit.plan,
            pursuitSpeedScale: pursuitSpeedScale
        )
    }

    static func wingmanHoldAtHub(
        wingmanVehicleID: String,
        fleetLink: FleetLinkService,
        fallbackAltitudeM: Double,
        fallbackHeadingDeg: Double
    ) -> FormationFollowStream.Target? {
        guard let hub = fleetLink.hubTelemetry(forVehicleID: wingmanVehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        return FormationFollowStream.Target(
            coord: RouteCoordinate(lat: lat, lon: lon),
            absoluteAltitudeM: hub.absoluteAltM ?? hub.altitudeAmslM ?? fallbackAltitudeM,
            yawDeg: MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub) ?? fallbackHeadingDeg,
            pursuitForwardMS: nil,
            pursuitYawspeedDegS: nil
        )
    }
}
