import Foundation

/// Designated learning squad selection (Alpha / first squad when unset or invalid).
enum TrainingLabLearningSquadSelection {
    static func clampedLearningSquadID(current: UUID?, squads: [TrainingLabSquad]) -> UUID? {
        let linked = squads.filter(\.hasLinkedSimulator)
        guard let firstID = linked.first?.id else { return nil }
        guard let current, linked.contains(where: { $0.id == current }) else { return firstID }
        return current
    }
}
