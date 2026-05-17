import Foundation
import Mavsdk

/// Convoy primary MAVLink: mission+geofence upload in compiling phase; arm+start after launch→WP1 (no re-upload).
@MainActor
enum MissionRunConvoyPrimaryMissionDispatch {

    struct EncodeOutcome {
        var command: MissionRunIssuedCommand?
        var events: [MissionRunEvent]
    }

    /// ``FleetCommandName/fleetVehicleDoMissionUpload`` — mission items then geofences (no arm/start).
    static func encodeMissionUploadCommand(
        squad: MissionRunPlannerSubsystem.PlannedTaskSquadMission,
        task: MissionTask,
        mission: Mission,
        environment: MissionRunEnvironment,
        issuerKey: String = MissionRunCommandIssuerKey.missionExecute
    ) -> EncodeOutcome {
        var events: [MissionRunEvent] = []
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: task.id,
            taskName: task.name,
            squadIndex: squad.squadIndex
        )
        guard let tokenKey = squad.squad.primaryAssignment.attachedFleetVehicleToken else {
            return EncodeOutcome(command: nil, events: events)
        }
        let plan = Mavsdk.Mission.MissionPlan(missionItems: squad.missionItems)
        let missionItemsJSON: String
        do {
            missionItemsJSON = try FleetVehicleCommandMissionItemPayload.encodeMissionPlanToJSON(plan: plan)
        } catch {
            events.append(
                MissionRunEvent(
                    level: .error,
                    taskID: squadLog.id,
                    taskLabel: squadLog.label,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionPlanItemsEncodeFailed,
                    templateParams: [
                        "slot": squad.squad.primaryAssignment.slotName,
                        "slotID": squad.squad.primaryAssignment.id.uuidString,
                        "reason": error.localizedDescription,
                    ]
                )
            )
            return EncodeOutcome(command: nil, events: events)
        }
        let geofencePolygonsJSON: String
        do {
            let hubForPx4Filter: FleetHubVehicleTelemetry? = {
                guard let fleetLink = environment.fleetLink,
                      let sitl = environment.sitl,
                      let token = FleetMissionVehicleToken(storageKey: tokenKey),
                      let vehicleID = resolvedFleetStreamVehicleID(
                        token: token,
                        fleetLink: fleetLink,
                        sitl: sitl
                      )
                else { return nil }
                return fleetLink.hubTelemetry(forVehicleID: vehicleID)
            }()
            let px4FilterHome = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(
                routeMacroHome: mission.routeMacro.home?.coord,
                hub: hubForPx4Filter
            )
            let (geofencesForPx4, omittedPx4Inclusions) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(
                fences: squad.effectiveGeofencesForSquad,
                home: px4FilterHome
            )
            if omittedPx4Inclusions > 0 {
                events.append(
                    MissionRunEvent(
                        level: .warning,
                        taskID: squadLog.id,
                        taskLabel: squadLog.label,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionGeofencePx4InclusionFencesOmitted,
                        templateParams: [
                            "count": String(omittedPx4Inclusions),
                            "slot": squad.squad.primaryAssignment.slotName,
                            "slotID": squad.squad.primaryAssignment.id.uuidString,
                        ]
                    )
                )
            }
            geofencePolygonsJSON = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(
                forGeofences: geofencesForPx4
            )
        } catch {
            events.append(
                MissionRunEvent(
                    level: .error,
                    taskID: squadLog.id,
                    taskLabel: squadLog.label,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionGeofencePolygonsEncodeFailed,
                    templateParams: [
                        "slot": squad.squad.primaryAssignment.slotName,
                        "slotID": squad.squad.primaryAssignment.id.uuidString,
                        "reason": error.localizedDescription,
                    ]
                )
            )
            return EncodeOutcome(command: nil, events: events)
        }
        let issued = MissionRunIssuedCommand(
            assignmentID: squad.squad.primaryAssignment.id,
            slotName: squad.squad.primaryAssignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: .catalogue(
                name: .fleetVehicleDoMissionUpload,
                parameters: FleetCommandParameters(values: [
                    "missionItemsJSON": .string(missionItemsJSON),
                    "geofencePolygonsJSON": .string(geofencePolygonsJSON),
                ])
            ),
            issuer: .missionControl,
            issuerKey: issuerKey,
            category: .missionControl
        )
        return EncodeOutcome(command: issued, events: events)
    }

    /// Exit OFFBOARD, set AUTO mission mode, arm, and start — after GR launch→WP1 when the plan is already onboard.
    static func startMissionAfterLaunchLegCommand(
        primaryAssignmentID: UUID,
        slotName: String,
        vehicleTokenKey: String,
        issuerKey: String = MissionRunCommandIssuerKey.missionExecute
    ) -> MissionRunIssuedCommand {
        MissionRunIssuedCommand(
            assignmentID: primaryAssignmentID,
            slotName: slotName,
            vehicleTokenKey: vehicleTokenKey,
            dispatch: .recipe(
                name: FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: issuerKey,
            category: .missionControl
        )
    }
}
