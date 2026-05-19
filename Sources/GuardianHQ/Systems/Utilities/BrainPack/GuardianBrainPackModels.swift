import Foundation

struct GuardianBrainPackManifest: Codable, Equatable, Sendable {
    var formatVersion: Int
    var brainId: UUID
    var brainVersion: GuardianBrainVersion
    var displayName: String
    var createdAt: Date
    var trainingAppBuild: String
    var vehicleClasses: [String]
    var taskKinds: [String]
    var gazeboEnvironmentId: String?

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case brainId = "brain_id"
        case brainVersion = "brain_version"
        case displayName = "display_name"
        case createdAt = "created_at"
        case trainingAppBuild = "training_app_build"
        case vehicleClasses = "vehicle_classes"
        case taskKinds = "task_kinds"
        case gazeboEnvironmentId = "gazebo_environment_id"
    }
}

struct GuardianBrainPackSkill: Codable, Equatable, Sendable {
    var segments: [TrainingControlSegment]
    var layout: TrainingTaskLayout
    var score: TrainingSkillScore
    var summary: String
}

struct GuardianBrainPackPlannerHints: Codable, Equatable, Sendable {
    var frameId: String?
    var maxSpeedMS: Double?
    var nav2ParamOverlayJSON: String?
    var aerostack2ParamOverlayJSON: String?

    enum CodingKeys: String, CodingKey {
        case frameId = "frame_id"
        case maxSpeedMS = "max_speed_m_s"
        case nav2ParamOverlayJSON = "nav2_param_overlay_json"
        case aerostack2ParamOverlayJSON = "aerostack2_param_overlay_json"
    }
}

struct GuardianBrainPackSquadProfile: Codable, Equatable, Sendable {
    var formationShape: String?
    var slotSpacingM: Double?
    var convoyOffsetsJSON: String?
}

struct GuardianBrainPackProvenance: Codable, Equatable, Sendable {
    var trialIndex: Int
    var simPlatform: String
    var worldHash: String?
    var checksumSHA256: String

    enum CodingKeys: String, CodingKey {
        case trialIndex = "trial_index"
        case simPlatform = "sim_platform"
        case worldHash = "world_hash"
        case checksumSHA256 = "checksum_sha256"
    }
}

struct GuardianBrainPack: Codable, Equatable, Sendable {
    var manifest: GuardianBrainPackManifest
    var skill: GuardianBrainPackSkill
    var plannerHints: GuardianBrainPackPlannerHints?
    var squadProfile: GuardianBrainPackSquadProfile?
    var provenance: GuardianBrainPackProvenance

    enum CodingKeys: String, CodingKey {
        case manifest
        case skill
        case plannerHints = "planner_hints"
        case squadProfile = "squad_profile"
        case provenance
    }
}

/// Catalogue row for Mission settings (imported packs on disk).
struct GuardianBrainCatalogueEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(manifest.brainId.uuidString)-\(manifest.brainVersion.semverString)" }
    let manifest: GuardianBrainPackManifest
    let packFileURL: URL
    let importedAt: Date
}

enum GuardianBrainPackError: LocalizedError, Equatable {
    case unsupportedFormatVersion(Int)
    case checksumMismatch
    case invalidFile(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "This brain pack uses format version \(version), which this app cannot import. \(GuardianBrainPackFormat.compatibilityMatrixSummary)"
        case .checksumMismatch:
            return "Brain pack checksum does not match file contents. The file may be damaged."
        case .invalidFile(let detail):
            return detail
        case .importFailed(let detail):
            return "Could not import brain pack: \(detail)"
        }
    }
}
