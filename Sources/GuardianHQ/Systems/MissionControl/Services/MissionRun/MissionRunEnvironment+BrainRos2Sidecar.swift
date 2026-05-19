import Foundation

extension MissionRunEnvironment {

    /// Enrolls PX4 roster streams in the fleet ROS 2 sidecar and attaches brain planner overlays for MCR.
    func syncBrainRos2SidecarEnrollment(sitl: SitlService) {
        guard let fleetLink, let mission = template, !brainBindings.isEmpty else { return }
        let enrollment = GuardianBrainRos2SidecarPolicy.missionEnrollment(
            mission: mission,
            assignments: assignments,
            bindings: brainBindings,
            fleetLink: fleetLink,
            sitl: sitl
        )
        guard !enrollment.enrollPX4VehicleIDs.isEmpty else { return }
        fleetLink.applyMissionBrainRos2SidecarPolicy(
            overlaysByVehicleID: enrollment.overlaysByVehicleID,
            enrollPX4VehicleIDs: enrollment.enrollPX4VehicleIDs,
            mergeOverlays: false
        )
    }

    /// Merges squad PX4 streams + brain overlays when convoy assembly starts (wingmen may enroll after run start).
    func syncSquadBrainRos2SidecarEnrollment(
        squad: MissionRunPlannerSubsystem.MissionTaskSquad,
        sitl: SitlService
    ) {
        guard let fleetLink, let mission = template else { return }
        let enrollment = GuardianBrainRos2SidecarPolicy.squadEnrollment(
            mission: mission,
            squad: squad,
            bindings: brainBindings,
            fleetLink: fleetLink,
            sitl: sitl
        )
        guard !enrollment.enrollPX4VehicleIDs.isEmpty else { return }
        fleetLink.applyMissionBrainRos2SidecarPolicy(
            overlaysByVehicleID: enrollment.overlaysByVehicleID,
            enrollPX4VehicleIDs: enrollment.enrollPX4VehicleIDs,
            mergeOverlays: true
        )
    }

    /// Drops mission-run brain overlays from the fleet ROS 2 reconcile path (run end / abort).
    func clearBrainRos2SidecarEnrollment() {
        fleetLink?.clearMissionBrainRos2SidecarPolicy()
    }
}
