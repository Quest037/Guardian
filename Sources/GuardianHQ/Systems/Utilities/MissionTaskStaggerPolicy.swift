import Foundation

/// First-wave primary squad spacing for ``MissionTask`` (MRE squads).
enum MissionTaskStaggerPolicy {
    /// Seconds between each primary's offset in the first launch wave.
    static func firstWaveStepSeconds(
        task: MissionTask,
        mission: Mission,
        squads: [MissionRunPlannerSubsystem.PlannedTaskSquadMission]
    ) -> TimeInterval {
        switch task.staggerTrigger {
        case .fixedInterval:
            return task.staggerIntervalTotalSeconds
        case .pathEstimate, .waypointReached, .operatorFirstWaveGate:
            return pathEstimateStepSeconds(task: task, squads: squads, mission: mission)
        }
    }

    /// Whether this squad is included in the automatic first-wave mission upload pass.
    static func includesSquadInAutomaticFirstWave(task: MissionTask, squadIndex: Int) -> Bool {
        squadIndex == 0 || !task.staggerTrigger.defersSubsequentPrimariesInFirstWave
    }

    /// True once when MAVLink ``missionProgressCurrent`` first reaches the gate derived from ``MissionTask/staggerWaypointIndex`` (0-based waypoint index in the task path).
    static func shouldAutoReleaseNextDeferredFirstWaveSquad(
        previousProgress: Int32,
        currentProgress: Int32,
        missionProgressTotal: Int32,
        staggerWaypointIndex: Int
    ) -> Bool {
        guard missionProgressTotal > 0 else { return false }
        let gate = Int32(min(max(0, staggerWaypointIndex) + 1, Int(missionProgressTotal)))
        return currentProgress >= gate && previousProgress < gate
    }

    /// Path-leg distance / speed estimate (5…300 s), used for automatic spacing and as interim spacing for deferred triggers.
    static func pathEstimateStepSeconds(
    task: MissionTask,
    squads: [MissionRunPlannerSubsystem.PlannedTaskSquadMission],
    mission: Mission
    ) -> TimeInterval {
        guard let firstWaypoint = task.waypoints.first else { return 20 }
        let distanceM: Double = {
            if task.waypoints.count > 1 {
                let second = task.waypoints[1]
                return MissionTelemetryGeo.horizontalDistanceM(
                    lat1: firstWaypoint.coord.lat,
                    lon1: firstWaypoint.coord.lon,
                    lat2: second.coord.lat,
                    lon2: second.coord.lon
                )
            }
            return 100
        }()
        let speedMps: Double = {
            let maybeWaypoint = firstWaypoint.transition.targetSpeed
            let waypointUnit = firstWaypoint.transition.speedUnit
            let fromWaypoint = waypointUnit == .kilometersPerHour ? (maybeWaypoint * 1000 / 3600) : maybeWaypoint
            let fallback = mission.routeMacro.rules.defaultSpeed
            return max(1, fromWaypoint > 0 ? fromWaypoint : fallback)
        }()
        let estimate = distanceM / speedMps
        return min(300, max(5, estimate))
    }
}
