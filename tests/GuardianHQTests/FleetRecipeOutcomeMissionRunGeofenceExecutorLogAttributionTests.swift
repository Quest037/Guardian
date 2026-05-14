import XCTest

@testable import GuardianHQ

final class FleetRecipeOutcomeMissionRunGeofenceExecutorLogAttributionTests: XCTestCase {

    func test_standaloneGeofenceUploadRecipe_anyFailure_countsAsGeofenceFleetFailure() throws {
        let geofenceUpload = try FleetRecipeName(validating: "recipe.fleet.do.geofence.upload")
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [FleetRecipeStepID.literal("uploadGeofence")],
            lastResponse: nil,
            detail: nil,
            trace: FleetRecipeAuditTrace(
                runID: FleetRecipeRunID(),
                recipe: geofenceUpload,
                vehicleID: "sim-1"
            )
        )
        XCTAssertTrue(outcome.isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: geofenceUpload))
    }

    func test_missionUploadRecipe_detailPrefixUploadGeofence_countsAsGeofenceFleetFailure() throws {
        let missionUploadStart = try FleetRecipeName(validating: "recipe.fleet.do.mission.upload.start")
        let resp = FleetCommandResponse.error(
            .unknown,
            detail: "upload geofence (1 polygon(s)) — rejected by FC",
            elapsed: 0.1
        )
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [FleetRecipeStepID.literal("upload")],
            lastResponse: resp,
            detail: nil,
            trace: FleetRecipeAuditTrace(
                runID: FleetRecipeRunID(),
                recipe: missionUploadStart,
                vehicleID: "sim-1"
            )
        )
        XCTAssertTrue(outcome.isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: missionUploadStart))
    }

    func test_missionUploadRecipe_detailMissionUploadOnly_notGeofenceAttributed() throws {
        let missionUploadStart = try FleetRecipeName(validating: "recipe.fleet.do.mission.upload.start")
        let resp = FleetCommandResponse.error(
            .unknown,
            detail: "upload mission (3 item(s)) — timeout",
            elapsed: 0.1
        )
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [FleetRecipeStepID.literal("upload")],
            lastResponse: resp,
            detail: nil,
            trace: FleetRecipeAuditTrace(
                runID: FleetRecipeRunID(),
                recipe: missionUploadStart,
                vehicleID: "sim-1"
            )
        )
        XCTAssertFalse(outcome.isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: missionUploadStart))
    }

    func test_failedPathIncludesUploadGeofenceStep_countsAsGeofenceFleetFailure() throws {
        let missionUploadStart = try FleetRecipeName(validating: "recipe.fleet.do.mission.upload.start")
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [FleetRecipeStepID.literal("uploadGeofence")],
            lastResponse: nil,
            detail: nil,
            trace: FleetRecipeAuditTrace(
                runID: FleetRecipeRunID(),
                recipe: missionUploadStart,
                vehicleID: "sim-1"
            )
        )
        XCTAssertTrue(outcome.isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: missionUploadStart))
    }

    func test_geofenceExecutorTemplateKeys_registeredInStructuredCatalog() {
        for key in [
            MissionRunLogTemplateKey.missionGeofencePolygonsEncodeFailed,
            MissionRunLogTemplateKey.missionGeofencePx4InclusionFencesOmitted,
            MissionRunLogTemplateKey.missionRunGeofenceFleetAckFailed,
            MissionRunLogTemplateKey.recipeFleetOutcomeTraceMismatch,
        ] {
            XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport), key)
            XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom), key)
        }
    }
}
