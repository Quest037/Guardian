import Foundation

/// Start-run gate: roster vehicles must not begin inside **exclusion** geofences (template + run augmentation).
enum MissionControlStartRunGeofenceValidationUtilities {

    struct ExclusionViolation: Equatable, Sendable {
        let assignmentID: UUID
        let slotDisplayName: String
        let fenceName: String
        let coordinate: RouteCoordinate
    }

    static let startRunInsideExclusionRemediation = PreflightFailureRemediationAdvice(
        patternId: "missioncontrol.start_run.inside_exclusion",
        summary: "This vehicle is inside an exclusion geofence.",
        steps: [
            "Move the vehicle outside exclusion zones, or drag its spawn marker on the Mission Control setup map.",
            "You can also adjust or remove the exclusion fence before starting the run.",
        ]
    )

    /// Roster slots in start-run preflight order that horizontally lie inside any **exclusion** fence for that slot.
    @MainActor
    static func exclusionViolations(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        launchCoordinateOverrides: [UUID: RouteCoordinate],
        resolveVehicleID: (MissionRunAssignment) -> String?
    ) -> [ExclusionViolation] {
        var out: [ExclusionViolation] = []
        for target in run.orderedStartRunPreflightProbeSequence(mission: mission) {
            let assignment = target.assignment
            guard let coordinate = resolvedStartCoordinate(
                assignment: assignment,
                launchCoordinateOverrides: launchCoordinateOverrides,
                fleetLink: fleetLink,
                resolveVehicleID: resolveVehicleID
            ) else { continue }

            let fences = MissionRunGeofencePolicyResolution.assignmentGeofences(
                assignment: assignment,
                mission: mission,
                missionWideRunAugmentation: run.policies.missionGeofenceAugmentation,
                perTaskRunAugmentationByTaskID: run.taskGeofenceAugmentationsByTaskID
            )
            guard let fence = firstContainingExclusion(coordinate: coordinate, geofences: fences) else { continue }
            let fenceLabel = fence.name.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(
                ExclusionViolation(
                    assignmentID: assignment.id,
                    slotDisplayName: target.displayTitle,
                    fenceName: fenceLabel.isEmpty ? "Exclusion geofence" : fenceLabel,
                    coordinate: coordinate
                )
            )
        }
        return out
    }

    static func failureDetail(for violation: ExclusionViolation) -> String {
        "Start run blocked — \(violation.slotDisplayName) is inside exclusion “\(violation.fenceName)”."
    }

    @MainActor
    static func resolvedStartCoordinate(
        assignment: MissionRunAssignment,
        launchCoordinateOverrides: [UUID: RouteCoordinate],
        fleetLink: FleetLinkService,
        resolveVehicleID: (MissionRunAssignment) -> String?
    ) -> RouteCoordinate? {
        if let override = launchCoordinateOverrides[assignment.id] {
            return override
        }
        guard let vehicleID = resolveVehicleID(assignment),
              let hub = fleetLink.hubTelemetryByVehicleID[vehicleID],
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        return RouteCoordinate(lat: lat, lon: lon)
    }

    static func firstContainingExclusion(
        coordinate: RouteCoordinate,
        geofences: [MissionGeofence]
    ) -> MissionGeofence? {
        for fence in geofences where fence.boundary == .exclusion {
            if MissionGeofenceLegalityUtilities.pointInsideFence(coordinate: coordinate, fence: fence) {
                return fence
            }
        }
        return nil
    }
}
