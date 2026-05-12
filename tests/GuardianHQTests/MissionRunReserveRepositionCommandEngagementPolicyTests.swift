import XCTest

@testable import GuardianHQ

final class MissionRunReserveRepositionCommandEngagementPolicyTests: XCTestCase {

    func test_engagement_action_mapping() {
        XCTAssertEqual(
            MissionRunReserveRepositionCommandEngagementPolicy.engagementAction(for: .cancelReturnToLaunchOnReserve),
            .rtl
        )
        XCTAssertEqual(
            MissionRunReserveRepositionCommandEngagementPolicy.engagementAction(for: .guidedGotoOrReposition),
            .swapInReserve
        )
        XCTAssertEqual(
            MissionRunReserveRepositionCommandEngagementPolicy.engagementAction(for: .loiterHold),
            .swapInReserve
        )
    }

    func test_gate_outcomes_by_disposition() {
        let auto = MissionRunReserveRepositionCommandEngagementPolicy.gateOutcome(
            disposition: .autonomous,
            action: .swapInReserve
        )
        guard case .allowImmediateDispatch = auto else { return XCTFail() }

        let forbid = MissionRunReserveRepositionCommandEngagementPolicy.gateOutcome(
            disposition: .forbidden,
            action: .rtl
        )
        guard case .blockForbidden(let act, _) = forbid else { return XCTFail() }
        XCTAssertEqual(act, .rtl)

        let ask = MissionRunReserveRepositionCommandEngagementPolicy.gateOutcome(
            disposition: .ask,
            action: .swapInReserve
        )
        guard case .requiresOperatorEngagement(let a, let d) = ask else { return XCTFail() }
        XCTAssertEqual(a, .swapInReserve)
        XCTAssertEqual(d, .ask)
    }

    @MainActor
    func test_run_gate_respects_policies_engagement() {
        let mission = Mission(name: "RoE", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        var policies = run.policies
        policies.engagement.perAction[.swapInReserve] = MissionRunEngagementRule(disposition: .forbidden)
        run.policies = policies

        let o = run.repositionReserveFleetVerbEngagementGate(for: .guidedGotoOrReposition)
        guard case .blockForbidden(let act, _) = o else { return XCTFail() }
        XCTAssertEqual(act, .swapInReserve)
    }
}
