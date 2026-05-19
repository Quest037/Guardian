import Foundation

/// Designated learning squad selection (Alpha / first squad when unset or invalid).
enum TrainingLabLearningSquadSelection {
    static func clampedLearningSquadID(current: UUID?, squads: [TrainingLabSquad]) -> UUID? {
        guard let firstID = squads.first?.id else { return nil }
        guard let current, squads.contains(where: { $0.id == current }) else { return firstID }
        return current
    }
}
