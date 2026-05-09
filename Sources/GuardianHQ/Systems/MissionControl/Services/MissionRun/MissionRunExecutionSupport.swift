import Foundation

@MainActor
enum MissionRunExecutionStage: Equatable {
    case idle
    case staging
    case running
    case paused
    case teardown
    case completed
    case failed
}

struct MissionRunExecutionCursor: Equatable {
    let activeTaskID: UUID?
    let cycleCount: Int
}

enum MissionRunExecutionStrategy: Equatable {
    case immediate
    case safePoint
    case nextCycle
}

enum MissionRunExecutionStopMode: Equatable {
    case immediate
    case afterCycle
}

struct MissionRunExecutionContext {
    let mission: Mission?
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let missionProvider: @MainActor () -> Mission?
}

enum MissionRunExecutionEvent: Equatable {
    case missionCycleFinished(vehicleID: String)
    case deferredTaskStartDue(taskID: UUID)
}

enum MissionRunExecutionDecision: Equatable {
    case noOp
    case started
    case progressed
    case paused
    case resumed
    case stopRequested(MissionRunExecutionStopMode)
    case completed(MissionRunCompletionKind)
}
