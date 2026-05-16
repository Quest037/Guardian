import Foundation

/// Operator **vehicle launch** poses for Mission Control runs — distinct from ``RouteMacro/home`` (first task waypoint for map authoring only).
@MainActor
enum MissionControlOperatorLaunchPosePolicy {

    static let returnToLaunchProcedureLogSummary = "Go to operator launch"

    /// Move+park recipe targeting the MCS-captured launch pose for this roster row.
    static func buildReturnToLaunchDispatch(
        launchPose: FleetSimState,
        planningRelativeAltitudeM: Double
    ) -> MissionRunFleetDispatch? {
        guard let params = try? MissionRunMovePointParkPlanner.buildExplicitMovePointParkRecipeParameters(
            latitudeDeg: launchPose.latitudeDeg,
            longitudeDeg: launchPose.longitudeDeg,
            relativeAltitudeM: planningRelativeAltitudeM,
            yawDeg: Double(launchPose.yawDeg),
            procedureLogSummary: returnToLaunchProcedureLogSummary
        ) else { return nil }
        return .recipe(
            name: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
            parameters: params
        )
    }

    /// Stack RTL when no operator launch was captured for this assignment.
    static var stackReturnToLaunchFallback: MissionRunFleetDispatch {
        .recipe(
            name: FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
            parameters: .empty
        )
    }

    /// Prefer MCS launch move+park; otherwise autopilot ``returnToLaunch()``.
    static func resolvedReturnToLaunchDispatch(
        assignmentID: UUID,
        launchPoseByAssignmentID: [UUID: FleetSimState],
        planningRelativeAltitudeM: Double
    ) -> MissionRunFleetDispatch {
        guard let pose = launchPoseByAssignmentID[assignmentID],
              let dispatch = buildReturnToLaunchDispatch(
                  launchPose: pose,
                  planningRelativeAltitudeM: planningRelativeAltitudeM
              )
        else {
            return stackReturnToLaunchFallback
        }
        return dispatch
    }
}
