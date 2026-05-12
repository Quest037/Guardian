import Foundation
import XCTest

@testable import GuardianHQ

final class ReserveSwapCandidateAliasTests: XCTestCase {

    func test_reserveSwapCandidate_typealias_is_same_type_as_mission_run_reserve_swap_candidate() {
        let tid = UUID()
        let slot = MissionRunReservePoolSlot(label: "A", attachedDevice: "d")
        let viaAlias: ReserveSwapCandidate = .floatingPool(taskID: tid, slot: slot)
        let viaEnum: MissionRunReserveSwapCandidate = viaAlias
        XCTAssertEqual(viaEnum, .floatingPool(taskID: tid, slot: slot))
    }

    func test_ranking_policy_pick_accepts_reserve_swap_candidate_arrays() {
        let tid = UUID()
        let slot = MissionRunReservePoolSlot(label: "Only", attachedDevice: "x")
        let c: ReserveSwapCandidate = .floatingPool(taskID: tid, slot: slot)
        let p = MissionRunReserveSwapRankingPolicy.uniformRandom
        XCTAssertEqual(p.pick(from: [c]), c)
    }
}
