import Combine
import Foundation
import Mavsdk

/// Core entry point for Paladin domains.
///
/// Paladin is an always-on app subsystem; domains stay mostly idle until invoked by
/// orchestrators (e.g. Mission Control running a mission).
@MainActor
final class PaladinEngine: ObservableObject {
    static let shared = PaladinEngine()

    let missionsDomain = PaladinMissionsDomain()
    let liveDriveDomain = PaladinLiveDriveDomain()
    let fleetDomain = PaladinFleetDomain()

    private init() {}

    // MARK: - Mission Control domain bridge

    func compileMissionControlPlan(
        run: MissionRun,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) -> PaladinPlan {
        PaladinCompiler.compile(run: run, mission: mission, fleetVehicles: fleetVehicles)
    }

    func executeMissionControlStagingPass(
        run: MissionRun,
        mission: Mission?
    ) -> PaladinRuntimePassResult {
        PaladinRuntime.executeStagingPass(run: run, mission: mission)
    }

    func executeMissionControlPrimaryMissionPass(
        run: MissionRun,
        mission: Mission,
        pathId: UUID? = nil
    ) -> PaladinRuntimePassResult {
        PaladinRuntime.executePrimaryMissionPass(run: run, mission: mission, pathId: pathId)
    }

    func buildMissionControlDronePathMission(
        run: MissionRun,
        mission: Mission,
        pathId: UUID
    ) -> (assignment: MissionRunAssignment, items: [Mavsdk.Mission.MissionItem])? {
        PaladinMavlinkMissionBuilder.buildDronePathMission(run: run, mission: mission, pathId: pathId)
    }

    func buildMissionControlSingleDronePathMission(
        run: MissionRun,
        mission: Mission
    ) -> (assignment: MissionRunAssignment, items: [Mavsdk.Mission.MissionItem])? {
        PaladinMavlinkMissionBuilder.buildSingleDronePathMission(run: run, mission: mission)
    }

    func missionControlMavlinkMissionProgressContext(
        run: MissionRun,
        mission: Mission
    ) -> (path: RoutePath, missionItemCount: Int)? {
        PaladinMavlinkMissionBuilder.mavlinkMissionProgressContext(run: run, mission: mission)
    }

    // MARK: - Other domain handles (stubs)

    func missionDomain() -> PaladinMissionsDomain {
        missionsDomain
    }

    func liveDriveDomainBridge() -> PaladinLiveDriveDomain {
        liveDriveDomain
    }

    func fleetDomainBridge() -> PaladinFleetDomain {
        fleetDomain
    }
}
