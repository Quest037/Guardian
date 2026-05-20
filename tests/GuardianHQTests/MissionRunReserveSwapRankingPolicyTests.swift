import Foundation
import XCTest

@testable import GuardianCore

final class MissionRunReserveSwapRankingPolicyTests: XCTestCase {

    func test_uniform_random_pick_returns_nil_when_empty() {
        let p = MissionRunReserveSwapRankingPolicy.uniformRandom
        XCTAssertNil(p.pick(from: []))
    }

    func test_uniform_random_pick_single_is_stable() {
        let tid = UUID()
        let slot = MissionRunReservePoolSlot(label: "Only", attachedDevice: "x")
        let c = MissionRunReserveSwapCandidate.floatingPool(taskID: tid, slot: slot)
        let p = MissionRunReserveSwapRankingPolicy.uniformRandom
        for _ in 0..<50 {
            XCTAssertEqual(p.pick(from: [c]), c)
        }
    }
}
