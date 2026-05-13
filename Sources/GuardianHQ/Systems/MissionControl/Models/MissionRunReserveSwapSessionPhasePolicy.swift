import Foundation

// MARK: - Reserve swap vs session phase

/// Gates **roster ↔ reserve** swap mutations (floating pool or fixed template reserve) while the run session is in a
/// terminal orchestration phase where swapping would fight recovery / completion / abort bookkeeping.
enum MissionRunReserveSwapSessionPhasePolicy: Sendable {

    /// When `false`, ``MissionRunEnvironment`` swap primitives and operator reserve-swap entrypoints must refuse new work.
    static func allowsReserveSwapMutation(sessionPhase: MissionRunSessionPhase) -> Bool {
        switch sessionPhase {
        case .recovery, .completed, .aborting, .aborted:
            return false
        case .draft, .compiled, .staging, .executing:
            return true
        }
    }
}
