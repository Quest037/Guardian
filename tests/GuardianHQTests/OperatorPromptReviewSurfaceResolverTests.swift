import XCTest
@testable import GuardianCore

final class OperatorPromptReviewSurfaceResolverTests: XCTestCase {

    override func tearDown() {
        OperatorPromptReviewSurfaceContributorRegistry.shared.unregisterContributor(id: "test.plugin.review")
        super.tearDown()
    }

    func test_mreEngagementAsk_withMissionRun_resolvesMissionControlFirst() {
        let runID = UUID()
        let taskID = UUID()
        let event = OperatorPromptEvent(
            origin: .mreEngagementAsk(runID: runID, action: .swapInReserve),
            target: OperatorPromptTarget(missionRunID: runID, missionTaskID: taskID),
            severity: .warning,
            title: "Swap?",
            body: "…",
            allowedVerbs: [.acknowledge, .abort]
        )
        guard case .missionControlRun(let rid, let tid) = OperatorPromptReviewSurfaceResolver.resolve(for: event) else {
            return XCTFail("expected mission control run")
        }
        XCTAssertEqual(rid, runID)
        XCTAssertEqual(tid, taskID)
    }

    func test_mreEngagementHandoff_vehicleOnly_resolvesLiveDriveBeforeMissionControl() {
        let runID = UUID()
        let event = OperatorPromptEvent(
            origin: .mreEngagementHandoff(runID: runID, action: .swapInReserve),
            target: OperatorPromptTarget(missionRunID: nil, missionTaskID: nil, affectedVehicleID: "V-99"),
            severity: .warning,
            title: "Handoff",
            body: "…",
            allowedVerbs: [.acknowledge, .abort]
        )
        guard case .liveDriveSession(let vid, let mrid) = OperatorPromptReviewSurfaceResolver.resolve(for: event) else {
            return XCTFail("expected live drive first for handoff with vehicle only")
        }
        XCTAssertEqual(vid, "V-99")
        XCTAssertNil(mrid)
    }

    func test_recipeEscalation_needsAirframeReplacement_withRun_skipsWizardPrefersMcr() {
        let runID = UUID()
        let esc = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"),
            vehicleID: "V-1",
            stepID: .literal("s"),
            reason: .unrecoverableFailure(kind: .needsAirframeReplacement),
            allowedVerbs: [.acknowledge],
            lastResponse: .success()
        )
        let event = OperatorPromptEvent(
            origin: .recipeEscalation(event: esc),
            target: OperatorPromptTarget(missionRunID: runID, missionTaskID: nil, affectedVehicleID: "V-1"),
            severity: .warning,
            title: "Replace?",
            body: "…",
            allowedVerbs: [.acknowledge]
        )
        guard case .missionControlRun(let rid, _) = OperatorPromptReviewSurfaceResolver.resolve(for: event) else {
            return XCTFail("expected MCR for mission-scoped airframe replacement policy")
        }
        XCTAssertEqual(rid, runID)
    }

    func test_recipeEscalation_vehicleOnly_skipsMcrAndWizard_resolvesLiveDrive() {
        let esc = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"),
            vehicleID: "V-2",
            stepID: .literal("s"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: [.acknowledge],
            lastResponse: .success()
        )
        let event = OperatorPromptEvent(
            origin: .recipeEscalation(event: esc),
            target: OperatorPromptTarget(missionRunID: nil, missionTaskID: nil, affectedVehicleID: "V-2"),
            severity: .warning,
            title: "Action",
            body: "…",
            allowedVerbs: [.acknowledge]
        )
        guard case .liveDriveSession(let vid, let mrid) = OperatorPromptReviewSurfaceResolver.resolve(for: event) else {
            return XCTFail("expected live drive when MCR cannot bind and wizard is skipped by resolver")
        }
        XCTAssertEqual(vid, "V-2")
        XCTAssertNil(mrid)
    }

    func test_contributorOverridesWhenBuiltInReturnsNil() {
        OperatorPromptReviewSurfaceContributorRegistry.shared.registerContributor(id: "test.plugin.review") { event in
            guard case .freeform(let src) = event.origin, src == "plugin.test.review" else { return nil }
            return .pluginSurface(applicationNamespace: "com.example.test", parameters: ["k": "v"])
        }
        let event = OperatorPromptEvent(
            origin: .freeform(source: "plugin.test.review"),
            target: .unspecified,
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge]
        )
        guard case .pluginSurface(let ns, let params) = OperatorPromptReviewSurfaceResolver.resolve(for: event) else {
            return XCTFail("expected contributor plugin surface")
        }
        XCTAssertEqual(ns, "com.example.test")
        XCTAssertEqual(params["k"], "v")
    }
}
