import XCTest

@testable import GuardianCore

final class MissionRunReserveSwapPostCommitPipelinePhaseResolverTests: XCTestCase {

    func test_mission_clear_maps_to_displaced_mission_clear() {
        let vac = UUID()
        let pool = UUID()
        let cor = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: UUID(),
            missionTaskID: UUID(),
            vacancyAssignmentID: vac,
            reserveStreamAssignmentID: pool,
            reservePoolSlotID: pool,
            vehicleID: "v1"
        )
        let issued = MissionRunIssuedCommand(
            assignmentID: pool,
            slotName: "pool",
            vehicleTokenKey: "live",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit
        )
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitPipelinePhaseResolver.phase(for: issued, correlation: cor),
            .displacedMissionClear
        )
    }

    func test_vacancy_upload_recipe_maps_to_mission_upload() {
        let vac = UUID()
        let pool = UUID()
        let cor = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: UUID(),
            missionTaskID: UUID(),
            vacancyAssignmentID: vac,
            reserveStreamAssignmentID: pool,
            reservePoolSlotID: pool,
            vehicleID: "v1"
        )
        let issued = MissionRunIssuedCommand(
            assignmentID: vac,
            slotName: "Primary",
            vehicleTokenKey: "live",
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"), parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit
        )
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitPipelinePhaseResolver.phase(for: issued, correlation: cor),
            .missionUpload
        )
    }

    func test_other_recipe_on_displaced_maps_to_displaced_fleet_wind_down() {
        let vac = UUID()
        let pool = UUID()
        let cor = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: UUID(),
            missionTaskID: UUID(),
            vacancyAssignmentID: vac,
            reserveStreamAssignmentID: pool,
            reservePoolSlotID: pool,
            vehicleID: "v1"
        )
        let issued = MissionRunIssuedCommand(
            assignmentID: pool,
            slotName: "pool",
            vehicleTokenKey: "live",
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.return.home"), parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit
        )
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitPipelinePhaseResolver.phase(for: issued, correlation: cor),
            .displacedFleetWindDown
        )
    }
}
