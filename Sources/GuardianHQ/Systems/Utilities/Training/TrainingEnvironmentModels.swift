import Foundation

/// Pose in environment-local ENU (metres + yaw degrees).
struct TrainingEnvironmentPose: Codable, Equatable, Sendable {
    var xM: Double
    var yM: Double
    var zM: Double
    var yawDeg: Double
}

enum TrainingEnvironmentSource: String, Codable, Sendable {
    case bundled
    case user
    case imported
}

/// Package manifest (`manifest.json`) inside each environment directory.
struct TrainingEnvironmentManifest: Codable, Equatable, Sendable {
    static let supportedFormatVersion = 1
    static let defaultBundledID = "guardian-open-field"

    var formatVersion: Int
    var id: String
    var displayName: String
    var description: String
    /// Path relative to the package root (e.g. `world.sdf`).
    var worldFile: String
    var tags: [String]
    /// `small` / `medium` / `large` — square floor side sets footprint (1 / 2 / 4 km²).
    var floorSize: String
    /// Terrain preset (`flat`, …) — selects world generation layout.
    var sceneType: String
    var defaultSpawn: TrainingEnvironmentPose
    var defaultGoal: TrainingEnvironmentPose

    init(
        formatVersion: Int = supportedFormatVersion,
        id: String,
        displayName: String,
        description: String = "",
        worldFile: String = "world.sdf",
        tags: [String] = [],
        floorSize: String = TrainingEnvironmentFloorSize.small.rawValue,
        sceneType: String = TrainingEnvironmentSceneType.flat.rawValue,
        defaultSpawn: TrainingEnvironmentPose,
        defaultGoal: TrainingEnvironmentPose
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.worldFile = worldFile
        self.tags = tags
        self.floorSize = floorSize
        self.sceneType = sceneType
        self.defaultSpawn = defaultSpawn
        self.defaultGoal = defaultGoal
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, id, displayName, description, worldFile, tags, floorSize, sceneType, defaultSpawn, defaultGoal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion)
            ?? TrainingEnvironmentManifest.supportedFormatVersion
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        worldFile = try c.decodeIfPresent(String.self, forKey: .worldFile) ?? "world.sdf"
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        floorSize = try c.decodeIfPresent(String.self, forKey: .floorSize)
            ?? TrainingEnvironmentFloorSize.small.rawValue
        sceneType = try c.decodeIfPresent(String.self, forKey: .sceneType)
            ?? TrainingEnvironmentSceneType.flat.rawValue
        defaultSpawn = try c.decode(TrainingEnvironmentPose.self, forKey: .defaultSpawn)
        defaultGoal = try c.decode(TrainingEnvironmentPose.self, forKey: .defaultGoal)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(description, forKey: .description)
        try c.encode(worldFile, forKey: .worldFile)
        try c.encode(tags, forKey: .tags)
        try c.encode(floorSize, forKey: .floorSize)
        try c.encode(sceneType, forKey: .sceneType)
        try c.encode(defaultSpawn, forKey: .defaultSpawn)
        try c.encode(defaultGoal, forKey: .defaultGoal)
    }
}

/// Resolved package on disk (bundled or user).
struct TrainingEnvironmentPackage: Identifiable, Equatable, Sendable {
    var id: String { manifest.id }
    let manifest: TrainingEnvironmentManifest
    let packageRootURL: URL
    let source: TrainingEnvironmentSource

    func worldFileURL() -> URL {
        packageRootURL.appendingPathComponent(manifest.worldFile, isDirectory: false)
    }
}

enum TrainingEnvironmentValidationError: LocalizedError, Equatable {
    case unsupportedFormatVersion(Int)
    case missingWorldFile(String)
    case emptyID
    case invalidIDCharacters

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let v):
            return "This environment uses format version \(v). This app supports version \(TrainingEnvironmentManifest.supportedFormatVersion) only."
        case .missingWorldFile(let path):
            return "World file is missing: \(path)"
        case .emptyID:
            return "Environment id is empty."
        case .invalidIDCharacters:
            return "Environment id may only contain letters, numbers, hyphens, and underscores."
        }
    }
}

enum TrainingEnvironmentValidator {
    static let idPattern = #"^[a-zA-Z0-9_-]+$"#

    static func validate(manifest: TrainingEnvironmentManifest, packageRoot: URL) throws {
        guard manifest.formatVersion == TrainingEnvironmentManifest.supportedFormatVersion else {
            throw TrainingEnvironmentValidationError.unsupportedFormatVersion(manifest.formatVersion)
        }
        let trimmedID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw TrainingEnvironmentValidationError.emptyID }
        guard trimmedID.range(of: idPattern, options: .regularExpression) != nil else {
            throw TrainingEnvironmentValidationError.invalidIDCharacters
        }
        let world = packageRoot.appendingPathComponent(manifest.worldFile, isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: world.path) else {
            throw TrainingEnvironmentValidationError.missingWorldFile(world.path)
        }
    }
}
