import Foundation

/// Class-aware ROS planner backend selection for MC-R squads (Nav2 ground/surface, Aerostack2 aerial).
@MainActor
enum GuardianSquadAutonomyPlannerRouting {

    struct SquadPlannerSummary: Equatable, Sendable {
        var primaryPlanner: GuardianAutonomyPlannerKind
        var wingmanPlanners: [GuardianAutonomyPlannerKind]

        var primaryToken: String { primaryPlanner.configToken }

        /// Compact operator/log token (e.g. `nav2` + wingmen `nav2,aerostack2`).
        var logSummary: String {
            let wingTokens = wingmanPlanners.map(\.configToken)
            if wingTokens.isEmpty {
                return primaryToken
            }
            return "\(primaryToken) + [\(wingTokens.joined(separator: ","))]"
        }
    }

    static func summary(
        primaryClass: FleetVehicleType,
        wingmanClasses: [FleetVehicleType]
    ) -> SquadPlannerSummary {
        SquadPlannerSummary(
            primaryPlanner: GuardianAutonomyPlannerRouting.defaultPlannerKind(for: primaryClass),
            wingmanPlanners: wingmanClasses.map { GuardianAutonomyPlannerRouting.defaultPlannerKind(for: $0) }
        )
    }

    static func summary(
        squad: MissionRunPlannerSubsystem.MissionTaskSquad
    ) -> SquadPlannerSummary {
        summary(
            primaryClass: squad.primaryRosterDevice.vehicleClass,
            wingmanClasses: squad.wingmanRosterDevices.map(\.vehicleClass)
        )
    }
}
