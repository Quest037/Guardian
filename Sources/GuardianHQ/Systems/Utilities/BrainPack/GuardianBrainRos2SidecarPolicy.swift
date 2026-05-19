import Foundation

/// Planner overlay + PX4 sidecar enrollment for Mission Control runs with brain bindings.
@MainActor
enum GuardianBrainRos2SidecarPolicy {

    struct MissionEnrollment: Equatable, Sendable {
        var overlaysByVehicleID: [String: Ros2BrainPlannerSidecarOverlay]
        var enrollPX4VehicleIDs: Set<String>
    }

    /// Resolves per-stream overlays from run bindings and roster slots with attached fleet tokens.
    static func missionEnrollment(
        mission: Mission,
        assignments: [MissionRunAssignment],
        bindings: [MissionRunBrainBinding],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionEnrollment {
        guard !bindings.isEmpty else {
            return MissionEnrollment(overlaysByVehicleID: [:], enrollPX4VehicleIDs: [])
        }
        var overlays: [String: Ros2BrainPlannerSidecarOverlay] = [:]
        var enroll: Set<String> = []
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })

        for assignment in assignments {
            guard let tokenKey = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tokenKey.isEmpty,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey),
                  let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
            else { continue }

            let fleetType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
                ?? rosterByID[assignment.rosterDeviceId]?.vehicleClass
                ?? .unknown
            let stack = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack ?? .unknown
            guard stack == .px4 else { continue }

            guard case .success = GuardianBrainDispatchResolver.resolve(
                fleetVehicleType: fleetType,
                bindings: bindings
            ) else { continue }

            enroll.insert(vehicleID)

            guard let binding = GuardianBrainRunUtilities.preferredBinding(for: fleetType, bindings: bindings),
                  let pack = try? GuardianBrainRunUtilities.loadPack(for: binding)
            else { continue }

            let hints = pack.plannerHints
            overlays[vehicleID] = Ros2BrainPlannerSidecarOverlay(
                brainId: binding.brainId,
                brainVersion: binding.brainVersion,
                nav2ParamOverlayJSON: hints?.nav2ParamOverlayJSON,
                aerostack2ParamOverlayJSON: hints?.aerostack2ParamOverlayJSON
            )
        }

        return MissionEnrollment(overlaysByVehicleID: overlays, enrollPX4VehicleIDs: enroll)
    }

    /// Enrolls every bound PX4 stream in a squad (primary + wingmen) for ROS sidecar reconcile.
    static func squadEnrollment(
        mission: Mission,
        squad: MissionRunPlannerSubsystem.MissionTaskSquad,
        bindings: [MissionRunBrainBinding],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionEnrollment {
        var assignments = [squad.primaryAssignment]
        assignments.append(contentsOf: squad.wingmanBindings.map(\.assignment))
        return missionEnrollment(
            mission: mission,
            assignments: assignments,
            bindings: bindings,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }
}

/// Per-vehicle brain planner metadata passed into the fleet ROS 2 sidecar reconcile path.
struct Ros2BrainPlannerSidecarOverlay: Equatable, Sendable {
    var brainId: UUID
    var brainVersion: GuardianBrainVersion
    var nav2ParamOverlayJSON: String?
    var aerostack2ParamOverlayJSON: String?
}
