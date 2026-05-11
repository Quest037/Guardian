import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlPreflightRecipeOutcomeMapperTests: XCTestCase {

    private let runID = FleetRecipeRunID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!)
    private let recipeName = FleetRecipeName.literal("recipe.fleet.diagnose.armprobe")
    private let vehicleID = "vehicle-test-1"

    private func traceAppendingArmStep(response: FleetCommandResponse) -> FleetRecipeAuditTrace {
        var trace = FleetRecipeAuditTrace(runID: runID, recipe: recipeName, vehicleID: vehicleID)
        trace.append(
            FleetRecipeAuditEntry(
                stepID: .literal("arm"),
                kind: .command(.fleetVehicleDoArm),
                attempt: 1,
                response: response,
                controlOutcome: .succeed
            )
        )
        return trace
    }

    func test_armedDuringSuccessfulProbe_trueWhenArmSucceeded() {
        let trace = traceAppendingArmStep(response: .success())
        XCTAssertTrue(MissionControlPreflightRecipeOutcomeMapper.armedDuringSuccessfulProbe(trace: trace))
    }

    func test_armedDuringSuccessfulProbe_falseWhenAlreadyArmed() {
        let trace = traceAppendingArmStep(response: .error(.alreadyArmed))
        XCTAssertFalse(MissionControlPreflightRecipeOutcomeMapper.armedDuringSuccessfulProbe(trace: trace))
    }

    func test_operatorFacingProbeFailureDetail_disarmPathReturnsRecipeDetailVerbatim() {
        let detail = MissionControlPreflightRecipeOutcomeMapper.operatorFacingProbeFailureDetail(
            failingCommandPath: [.literal("disarm")],
            recipeDetail: "Vehicle armed but did not disarm cleanly — UNSAFE STATE.",
            lastResponse: nil,
            hub: nil
        )
        XCTAssertTrue(detail.contains("UNSAFE"))
        XCTAssertFalse(detail.hasPrefix("Arm failed:"), "Disarm failures must not use the arm-step prefix.")
    }

    func test_operatorFacingProbeFailureDetail_armPathUsesArmFailedPrefix() {
        let detail = MissionControlPreflightRecipeOutcomeMapper.operatorFacingProbeFailureDetail(
            failingCommandPath: [.literal("arm")],
            recipeDetail: "Autopilot refused arm.",
            lastResponse: nil,
            hub: nil
        )
        XCTAssertTrue(detail.hasPrefix("Arm failed:"))
    }

    func test_singleVehiclePreflightProbeResult_successMapsArmedDuringProbe() {
        let trace = traceAppendingArmStep(response: .success())
        let outcome = FleetRecipeOutcome.succeeded(detail: nil, payload: .empty, trace: trace)
        let result = MissionControlPreflightRecipeOutcomeMapper.singleVehiclePreflightProbeResult(
            recipeOutcome: outcome,
            hub: nil,
            isSimulation: false
        )
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.armedDuringProbe)
        XCTAssertEqual(result.detail, "Arm succeeded.")
        XCTAssertNil(result.remediationAdvice)
    }

    func test_singleVehiclePreflightProbeResult_failureArmStepCarriesAdvice() {
        let trace = FleetRecipeAuditTrace(runID: runID, recipe: recipeName, vehicleID: vehicleID)
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [.literal("arm")],
            lastResponse: .error(.armRejectedByAutopilot, detail: "GPS"),
            detail: "Autopilot refused arm. Inspect the audit trace for the underlying reason (GPS lock, battery, levelling, calibration state, etc.).",
            trace: trace
        )
        let result = MissionControlPreflightRecipeOutcomeMapper.singleVehiclePreflightProbeResult(
            recipeOutcome: outcome,
            hub: nil,
            isSimulation: true
        )
        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.armedDuringProbe)
        XCTAssertTrue(result.detail.hasPrefix("Arm failed:"))
        XCTAssertNotNil(result.remediationAdvice)
    }
}
