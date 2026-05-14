import Foundation
import Mavsdk

extension MissionRunLogTemplateKey {
    /// Summary after MC-R pushes resolved geofences to all fleet-bound roster slots.
    static let mcrLiveGeofenceFleetPushSummary = "missioncontrol.mcr.live_geofence_fleet_push_summary"
    /// No compiled squad mission for the slot — geofence push falls back to standalone upload only.
    static let missionGeofenceFleetPushMissionPlanMissing = "missioncontrol.mcr.live_geofence_fleet_push_mission_plan_missing"
}

extension MissionRunEnvironment {
    /// Primary squad for this slot’s compiled waypoint list — used so MC-R fence pushes can use
    /// ``FleetCommandName/fleetVehicleDoMissionUpload`` (mission **before** geofence), matching
    /// ``FleetCommandStackConverterShared/translateMissionUpload`` and avoiding PX4/MAVSDK
    /// `Geofence.invalidArgument` when the onboard mission is still empty.
    private func mcrPlannedSquadMissionForLiveGeofenceFleetPush(
        assignment: MissionRunAssignment,
        mission: Mission
    ) -> MissionRunPlannerSubsystem.PlannedTaskSquadMission? {
        guard let tid = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission) else {
            return nil
        }
        let squads = systems.planner.buildTaskSquadMissions(mission: mission, taskId: tid)
        guard !squads.isEmpty else { return nil }
        if let direct = squads.first(where: { $0.squad.primaryAssignment.id == assignment.id }) {
            return direct
        }
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        guard let dev = rosterByID[assignment.rosterDeviceId],
              dev.slot == .wingman,
              let leaderRosterDeviceId = dev.leaderRosterDeviceId,
              let primaryAssignment = assignments.first(where: { $0.rosterDeviceId == leaderRosterDeviceId })
        else {
            return squads.first
        }
        return squads.first(where: { $0.squad.primaryAssignment.id == primaryAssignment.id }) ?? squads.first
    }

    /// MC-R: upload the **per-slot** resolved geofence union (template + run augmentations + slot augmentation)
    /// to every roster row with a fleet binding.
    ///
    /// When there are polygons to send and a compiled squad mission exists, uses
    /// ``FleetCommandName/fleetVehicleDoMissionUpload`` so the stack is **mission upload → clear geofence → upload geofence**
    /// (see ``FleetCommandStackConverterShared/translateMissionUpload``). That ordering avoids common
    /// PX4 / ArduPilot / MAVSDK failures from uploading fences while the onboard mission plan is empty.
    ///
    /// Falls back to ``FleetMissionRecipeRegistrations/doGeofenceUploadRecipeName`` only when no waypoint
    /// mission can be built for the slot (e.g. unresolved task binding). Clears onboard fences via
    /// ``FleetMissionRecipeRegistrations/doGeofenceClearRecipeName`` when the PX4-filtered set is empty.
    @MainActor
    func mcrUploadResolvedGeofencesToAllFleetAssignments(
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> (attempted: Int, succeeded: Int) {
        FleetMissionRecipeRegistrations.registerAll()
        guard let mission = template else { return (0, 0) }
        var attempted = 0
        var succeeded = 0
        for assignment in assignments {
            guard assignment.hasFleetOrLegacyAssignment,
                  let raw = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }
            attempted += 1
            let fences = MissionRunGeofencePolicyResolution.squadGeofences(
                primaryAssignment: assignment,
                mission: mission,
                missionWideRunAugmentation: policies.missionGeofenceAugmentation,
                perTaskRunAugmentationByTaskID: taskGeofenceAugmentationsByTaskID
            )
            let hubForPx4Filter: FleetHubVehicleTelemetry? = {
                guard let token = FleetMissionVehicleToken(storageKey: raw),
                      let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
                else { return nil }
                return fleetLink.hubTelemetry(forVehicleID: vehicleID)
            }()
            let px4FilterHome = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(
                routeMacroHome: mission.routeMacro.home?.coord,
                hub: hubForPx4Filter
            )
            let (geofencesForPx4, omittedPx4Inclusions) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(
                fences: fences,
                home: px4FilterHome
            )
            let pc = MissionControlTaskTagName.taskContext(for: assignment, mission: mission)
            if omittedPx4Inclusions > 0 {
                systems.logging.appendLogEvent(
                    level: .warning,
                    taskID: pc?.id,
                    taskLabel: pc?.label,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionGeofencePx4InclusionFencesOmitted,
                    templateParams: [
                        "count": String(omittedPx4Inclusions),
                        "slot": assignment.slotName,
                        "slotID": assignment.id.uuidString,
                    ]
                )
            }
            let dispatch: MissionRunFleetDispatch
            if geofencesForPx4.isEmpty {
                dispatch = .recipe(
                    name: FleetMissionRecipeRegistrations.doGeofenceClearRecipeName,
                    parameters: .empty
                )
            } else {
                let geofenceJSON: String
                do {
                    geofenceJSON = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: geofencesForPx4)
                } catch {
                    systems.logging.appendLogEvent(
                        level: .error,
                        taskID: pc?.id,
                        taskLabel: pc?.label,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionGeofencePolygonsEncodeFailed,
                        templateParams: [
                            "slotID": assignment.id.uuidString,
                            "reason": error.localizedDescription,
                        ]
                    )
                    continue
                }
                if let squad = mcrPlannedSquadMissionForLiveGeofenceFleetPush(assignment: assignment, mission: mission),
                   !squad.missionItems.isEmpty {
                    do {
                        let plan = Mavsdk.Mission.MissionPlan(missionItems: squad.missionItems)
                        let missionItemsJSON = try FleetVehicleCommandMissionItemPayload.encodeMissionPlanToJSON(plan: plan)
                        dispatch = .catalogue(
                            name: .fleetVehicleDoMissionUpload,
                            parameters: FleetCommandParameters(values: [
                                "missionItemsJSON": .string(missionItemsJSON),
                                "geofencePolygonsJSON": .string(geofenceJSON),
                            ])
                        )
                    } catch {
                        systems.logging.appendLogEvent(
                            level: .error,
                            taskID: pc?.id,
                            taskLabel: pc?.label,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.missionPlanItemsEncodeFailed,
                            templateParams: [
                                "slot": assignment.slotName,
                                "slotID": assignment.id.uuidString,
                                "reason": error.localizedDescription,
                            ]
                        )
                        continue
                    }
                } else {
                    systems.logging.appendLogEvent(
                        level: .warning,
                        taskID: pc?.id,
                        taskLabel: pc?.label,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionGeofenceFleetPushMissionPlanMissing,
                        templateParams: [
                            "slot": assignment.slotName,
                            "slotID": assignment.id.uuidString,
                        ]
                    )
                    dispatch = .recipe(
                        name: FleetMissionRecipeRegistrations.doGeofenceUploadRecipeName,
                        parameters: FleetRecipeParameters(values: ["geofencePolygonsJSON": .string(geofenceJSON)])
                    )
                }
            }
            let issued = MissionRunIssuedCommand(
                assignmentID: assignment.id,
                slotName: assignment.slotName,
                vehicleTokenKey: raw,
                dispatch: dispatch,
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.mcrLiveGeofenceFleetPush
            )
            let ok: Bool
            switch dispatch {
            case .catalogue:
                ok = await systems.commands.awaitCatalogueDispatchAndAckLogs(
                    issued: issued,
                    fleetLink: fleetLink,
                    sitl: sitl
                )
            case .recipe:
                ok = await systems.commands.awaitRecipeDispatchAppendingDispatchedThenAckLogs(
                    issued: issued,
                    fleetLink: fleetLink,
                    sitl: sitl
                )
            case .vehicleCommand:
                ok = false
            }
            if ok { succeeded += 1 }
        }
        systems.logging.appendLogEvent(
            level: attempted > 0 && succeeded == attempted ? .info : .warning,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.mcrLiveGeofenceFleetPushSummary,
            templateParams: [
                "attempted": "\(attempted)",
                "succeeded": "\(succeeded)",
            ]
        )
        return (attempted, succeeded)
    }
}
