import Foundation

@MainActor
final class PaladinMissionsDomain: ObservableObject {
    struct MissionSupportSnapshot: Equatable {
        var activeRunCount: Int
        var supportedMissionCount: Int

        static let empty = MissionSupportSnapshot(activeRunCount: 0, supportedMissionCount: 0)
    }

    @Published private(set) var latestSnapshot: MissionSupportSnapshot = .empty

    /// Stub entrypoint for cross-system mission support APIs.
    /// TODO: Implement mission-domain orchestration (templates, rosters, handover policies).
    func refreshMissionSupportSnapshot(activeRunCount: Int, supportedMissionCount: Int) {
        latestSnapshot = MissionSupportSnapshot(
            activeRunCount: max(0, activeRunCount),
            supportedMissionCount: max(0, supportedMissionCount)
        )
    }
}
