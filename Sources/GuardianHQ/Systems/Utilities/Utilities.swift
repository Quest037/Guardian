import Foundation
import Mavsdk

@MainActor
final class GlobalUtilities {
    let mission = MissionUtilities()
    let movements = MovementsUtilities()
    let fleet = FleetUtilities()
    let liveLeafletMap = LiveLeafletMapUtilitiesNamespace()
}

@MainActor
enum Utilities {
    private static let global = GlobalUtilities()

    static var mission: MissionUtilities { global.mission }
    static var movements: MovementsUtilities { global.movements }
    static var fleet: FleetUtilities { global.fleet }
    static var liveLeafletMap: LiveLeafletMapUtilitiesNamespace { global.liveLeafletMap }
}

/// Namespace for ``LiveLeafletMapMarkerBuildInputs`` and Phase B marker builder APIs.
@MainActor
struct LiveLeafletMapUtilitiesNamespace {
    /// Shared roster-art cache for live maps (MC-R, Live Drive, MCS). Safe across hub ticks.
    let markerImageCache = LiveLeafletMapMarkerCache()

    typealias MarkerBuildInputs = LiveLeafletMapMarkerBuildInputs
    typealias MarkerFocus = LiveLeafletMapMarkerFocus
    typealias MarkerImageCache = LiveLeafletMapMarkerCache
    typealias MarkerBuildResult = LiveLeafletMapMarkerBuildResult

    func buildMapVehicleMarkersLive(
        inputs: LiveLeafletMapMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache? = nil,
        rosterAccessibilityTitle: ((MissionRunAssignment, Mission) -> String?)? = nil
    ) -> LiveLeafletMapMarkerBuildResult {
        let cache = imageCache ?? markerImageCache
        return LiveLeafletMapUtilities.buildMapVehicleMarkersLive(
            inputs: inputs,
            imageCache: cache,
            rosterAccessibilityTitle: rosterAccessibilityTitle
        )
    }

    func buildMCSStagingMapVehicleMarkers(
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache? = nil
    ) -> LiveLeafletMapMarkerBuildResult {
        let cache = imageCache ?? markerImageCache
        return LiveLeafletMapUtilities.buildMCSStagingMapVehicleMarkers(inputs: inputs, imageCache: cache)
    }
}

@MainActor
final class MovementsUtilities {
    let sequenceStore = GuardianMovementSequenceStore()

    func planSlotApproach(
        _ context: GuardianMovementSlotApproachContext,
        vehicleID: String? = nil
    ) -> (plan: GuardianMovementPursuitPlan, declined: [GuardianMovementID]) {
        GuardianMovementPlanner.planSlotApproach(
            context,
            vehicleID: vehicleID,
            sequenceStore: sequenceStore
        )
    }

    func formationSlotPursuit(
        slot: RouteCoordinate,
        targetHeadingDeg: Double,
        vehicleType: FleetVehicleType,
        hub: FleetHubVehicleTelemetry?,
        primarySpeedMS: Double?,
        wingmanVehicleID: String? = nil,
        directSlotBeyondM: Double = MissionSquadConvoyFollowControlPolicy.directSlotBeyondM
    ) -> GuardianFormationSlotPursuitPlanning.Result? {
        GuardianFormationSlotPursuitPlanning.plan(
            slot: slot,
            targetHeadingDeg: targetHeadingDeg,
            vehicleType: vehicleType,
            hub: hub,
            primarySpeedMS: primarySpeedMS,
            wingmanVehicleID: wingmanVehicleID,
            sequenceStore: sequenceStore,
            directSlotBeyondM: directSlotBeyondM
        )
    }

    func supportedMovements(for vehicleType: FleetVehicleType) -> [GuardianMovementID] {
        GuardianMovementCapabilities.supportedMovements(vehicleType: vehicleType)
    }
}

@MainActor
final class MissionUtilities {
    let path = MissionPathUtilities()
    let squadFormation = MissionSquadFormationUtilities()
    let templateGeofences = MissionTemplateGeofenceUtilities()
    let geofenceGeometry = MissionGeofenceGeometryUtilities()

    /// MAVSDK geofence wire JSON for fleet upload (``FleetVehicleCommandGeofenceUploadPayload``: polygons + circles).
    func geofencePolygonsJSON(forGeofences fences: [MissionGeofence]) throws -> String {
        try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: fences)
    }
}

@MainActor
final class MissionSquadFormationUtilities {
    func desiredPadSlot(
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

    func bodyOffset(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> MissionSquadFormationGeometry.BodyOffsetMeters {
        MissionSquadFormationGeometry.bodyOffsetMeters(
            formation: formation,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
    }

    func pathBehindMeters(
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

    func resolvedFormationHeadingDeg(
        primaryHeadingDeg: Double,
        source: MissionSquadFormationHeadingPolicy.Source = .matchPrimary,
        fallbackHeadingDeg: Double? = nil
    ) -> Double {
        MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
            source: source,
            primaryHeadingDeg: primaryHeadingDeg,
            fallbackHeadingDeg: fallbackHeadingDeg
        )
    }
}

@MainActor
final class MissionPathUtilities {
    let waypoint = MissionPathWaypointUtilities()
}

@MainActor
final class MissionPathWaypointUtilities {
    func mavItem(
        coord: RouteCoordinate,
        waypoint: RouteWaypoint,
        useWaypointHeadingForYaw: Bool,
        loiterOverrideSeconds: Float? = nil
    ) -> Mavsdk.Mission.MissionItem {
        let relAlt = relativeAltitudeM(waypoint: waypoint)
        let speed = speedMetersPerSecond(waypoint: waypoint)
        let loiter = loiterOverrideSeconds ?? delaySeconds(waypoint: waypoint)
        let yaw: Float = useWaypointHeadingForYaw ? Float(waypoint.heading) : 0
        return Mavsdk.Mission.MissionItem(
            latitudeDeg: coord.lat,
            longitudeDeg: coord.lon,
            relativeAltitudeM: relAlt,
            speedMS: speed,
            isFlyThrough: false,
            gimbalPitchDeg: 0,
            gimbalYawDeg: 0,
            cameraAction: .none,
            loiterTimeS: loiter,
            cameraPhotoIntervalS: 0,
            acceptanceRadiusM: 3,
            yawDeg: yaw,
            cameraPhotoDistanceM: 0
        )
    }

    func relativeAltitudeM(waypoint: RouteWaypoint) -> Float {
        let v = waypoint.altitude.value
        switch waypoint.altitude.reference {
        case .agl:
            return Float(max(5, v))
        case .msl, .asl:
            return Float(max(5, v))
        }
    }

    func speedMetersPerSecond(waypoint: RouteWaypoint) -> Float {
        let t = waypoint.transition
        let s = t.targetSpeed
        switch t.speedUnit {
        case .metersPerSecond:
            return Float(max(1, s))
        case .kilometersPerHour:
            return Float(max(1, s / 3.6))
        }
    }

    func delaySeconds(waypoint: RouteWaypoint) -> Float {
        switch waypoint.delayUnit {
        case .secs:
            return Float(max(0, waypoint.delaySec))
        case .mins:
            return Float(max(0, waypoint.delaySec * 60))
        case .hrs:
            return Float(max(0, waypoint.delaySec * 3600))
        }
    }

    func shouldIgnoreClosingWaypointDelay(path: MissionTask, index: Int, waypoint: RouteWaypoint) -> Bool {
        guard path.waypoints.count >= 2, index == path.waypoints.count - 1 else { return false }
        guard let first = path.waypoints.first else { return false }
        guard waypointHasNoAction(waypoint) else { return false }
        return coordinatesNearlyEqual(first.coord, waypoint.coord)
    }

    func waypointHasNoAction(_ waypoint: RouteWaypoint) -> Bool {
        let normalized = waypoint.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "none"
    }

    private func coordinatesNearlyEqual(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Bool {
        let epsilon = 0.0000001
        return abs(a.lat - b.lat) <= epsilon && abs(a.lon - b.lon) <= epsilon
    }
}

@MainActor
final class FleetUtilities {
    let vehicle = FleetVehicleUtilities()
}

@MainActor
final class FleetVehicleUtilities {}
