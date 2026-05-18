import Foundation

/// Training panel vehicle picker (maps to SITL preset + ``FleetVehicleType``).
enum TrainingVehicleClass: String, CaseIterable, Identifiable, Codable, Sendable {
    case uavCopter
    case ugvWheeled
    case ugvTracked

    /// Temporary product lock: Training → Vehicle panel offers UGV-W and UGV-T only.
    static let trainingPanelSelectableCases: [TrainingVehicleClass] = [.ugvWheeled, .ugvTracked]

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .uavCopter: return "UAV-C"
        case .ugvWheeled: return "UGV-W"
        case .ugvTracked: return "UGV-T"
        }
    }

    var simulationPreset: SimulationVehiclePreset {
        switch self {
        case .uavCopter: return .uavMultirotor
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        }
    }

    var fleetVehicleType: FleetVehicleType {
        switch self {
        case .uavCopter: return .uavCopter
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        }
    }
}

enum TrainingPanelMode: String, CaseIterable, Identifiable, Sendable {
    case vehicle = "Vehicle"
    case formation = "Formation"

    var id: String { rawValue }
}

enum TrainingTaskKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case reverseIntoSlot = "reverseIntoSlot"
    case approachSlotForward = "approachSlotForward"
    case alignHeadingAtSlot = "alignHeadingAtSlot"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .reverseIntoSlot: return "Reverse into slot"
        case .approachSlotForward: return "Approach slot (forward)"
        case .alignHeadingAtSlot: return "Align heading at slot"
        }
    }

    var summary: String {
        switch self {
        case .reverseIntoSlot:
            return "Reach the target slot using reverse and turns; forward driving forbidden by default."
        case .approachSlotForward:
            return "Reach the target slot using forward motion and turns."
        case .alignHeadingAtSlot:
            return "Hold at the slot and match target heading using turns."
        }
    }

    var defaultForbiddenAxes: Set<TrainingControlAxis> {
        switch self {
        case .reverseIntoSlot:
            return [.driveForward]
        case .approachSlotForward:
            return [.driveReverse]
        case .alignHeadingAtSlot:
            return [.driveForward, .driveReverse]
        }
    }
}

struct TrainingTaskPose: Codable, Equatable, Sendable {
    var latitudeDeg: Double
    var longitudeDeg: Double
    var headingDeg: Double
    var absoluteAltitudeM: Double
}

/// Start pose + operator-placed target slot (goal is always ``targetSlot``, not derived from task).
struct TrainingTaskLayout: Codable, Equatable, Sendable {
    var start: TrainingTaskPose
    var goal: TrainingTaskPose
}

enum TrainingTaskLayoutFactory {
    static func startPose(spawn: SimSpawnDefaults) -> TrainingTaskPose {
        TrainingTaskPose(
            latitudeDeg: spawn.latitudeDeg,
            longitudeDeg: spawn.longitudeDeg,
            headingDeg: spawn.headingDeg,
            absoluteAltitudeM: spawn.altitudeM
        )
    }

    /// First-time default for the draggable target slot (not tied to task kind).
    static func defaultTargetSlot(spawn: SimSpawnDefaults) -> TrainingTaskPose {
        let offset = MissionSquadFormationGeometry.offsetCoordinate(
            latitudeDeg: spawn.latitudeDeg,
            longitudeDeg: spawn.longitudeDeg,
            headingDeg: spawn.headingDeg,
            forwardMeters: 8,
            rightMeters: 0
        )
        return TrainingTaskPose(
            latitudeDeg: offset.lat,
            longitudeDeg: offset.lon,
            headingDeg: spawn.headingDeg,
            absoluteAltitudeM: spawn.altitudeM
        )
    }

    static func layout(start: TrainingTaskPose, goal: TrainingTaskPose) -> TrainingTaskLayout {
        TrainingTaskLayout(start: start, goal: goal)
    }

    /// Legacy helper for tests — explicit start and goal.
    static func layout(kind: TrainingTaskKind, spawn: SimSpawnDefaults) -> TrainingTaskLayout {
        layout(start: startPose(spawn: spawn), goal: defaultTargetSlot(spawn: spawn))
    }
}

struct TrainingSkillScore: Codable, Equatable, Sendable {
    var positionErrorM: Double
    var headingErrorDeg: Double
    var episodeDurationS: Double
    var constraintViolations: [TrainingControlAxis]
    var succeeded: Bool
}

struct TrainedVehicleSkill: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var taskKind: TrainingTaskKind
    var vehicleClass: TrainingVehicleClass
    var segments: [TrainingControlSegment]
    var score: TrainingSkillScore
    var layout: TrainingTaskLayout
    var promotedAt: Date
    var trialIndex: Int
    var summary: String

    init(
        id: UUID = UUID(),
        taskKind: TrainingTaskKind,
        vehicleClass: TrainingVehicleClass,
        segments: [TrainingControlSegment],
        score: TrainingSkillScore,
        layout: TrainingTaskLayout,
        promotedAt: Date = Date(),
        trialIndex: Int,
        summary: String
    ) {
        self.id = id
        self.taskKind = taskKind
        self.vehicleClass = vehicleClass
        self.segments = segments
        self.score = score
        self.layout = layout
        self.promotedAt = promotedAt
        self.trialIndex = trialIndex
        self.summary = summary
    }
}

/// Candidate skill the autonomous teacher will attempt.
struct TrainingSkillCandidate: Equatable, Sendable {
    let trialIndex: Int
    let segments: [TrainingControlSegment]
    let summary: String
    let predictedPath: [RouteCoordinate]
}
