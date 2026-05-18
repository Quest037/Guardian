import Foundation

enum TrainingPanelPhase: Equatable, Sendable {
    case idle
    case spawning
    case connecting
    case preflight
    case teaching
    case promoted
    case exhausted
}

struct TrainingPanelLogLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let message: String

    init(message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
    }
}
