import Foundation

/// Authoring-time validation and draft helpers for World Builder.
enum TrainingEnvironmentAuthoring {
    static let maxAnchorAbsM = 500.0
    static let maxDisplayNameLength = 80
    static let maxDescriptionLength = 500

    /// URL-safe environment folder id from operator display name (not guaranteed unique).
    static func slugFromDisplayName(_ displayName: String) -> String {
        let slug = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^a-z0-9_-]"#, with: "", options: .regularExpression)
        let trimmed = String(slug.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if trimmed.count >= 3 { return trimmed }
        return "world-\(UUID().uuidString.prefix(8).lowercased())"
    }

    static func newDraftID(from displayName: String) -> String {
        slugFromDisplayName(displayName)
    }

    /// Picks `slug`, or `slug-2`, `slug-3`, … so the id does not appear in `occupiedIDs` (optionally ignoring one reserved id).
    static func uniqueEnvironmentID(
        slug: String,
        occupiedIDs: Set<String>,
        excludingEnvironmentID: String? = nil
    ) -> String {
        let base = slugFromDisplayName(slug)
        func isAvailable(_ candidate: String) -> Bool {
            if candidate == excludingEnvironmentID { return true }
            return !occupiedIDs.contains(candidate)
        }
        if isAvailable(base) { return base }
        var ticker = 2
        while ticker < 10_000 {
            let candidate = "\(base)-\(ticker)"
            if isAvailable(candidate) { return candidate }
            ticker += 1
        }
        return "\(base)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    static func newDraftManifest(
        displayName: String = "New training world",
        floorSize: TrainingEnvironmentFloorSize = .small,
        sceneType: TrainingEnvironmentSceneType = .flat
    ) -> TrainingEnvironmentManifest {
        let id = slugFromDisplayName(displayName)
        return TrainingEnvironmentManifest(
            id: id,
            displayName: displayName,
            description: "",
            tags: ["ugv"],
            floorSize: floorSize.rawValue,
            sceneType: sceneType.rawValue,
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0.1, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 8, yM: 0, zM: 0.1, yawDeg: 0)
        )
    }

    /// Writes a fresh `world.sdf` for a new user package from manifest floor + scene presets.
    static func writeNewWorldFile(
        environmentID: String,
        floorSize: TrainingEnvironmentFloorSize,
        sceneType: TrainingEnvironmentSceneType,
        to url: URL
    ) throws {
        switch sceneType {
        case .flat:
            try TrainingEnvironmentWorldSDF.writeOpenFieldWorld(
                to: url,
                environmentID: environmentID,
                floorSideM: floorSize.floorSideM
            )
        }
    }

    static func validateManifest(_ manifest: TrainingEnvironmentManifest) throws {
        let name = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TrainingEnvironmentAuthoringError.emptyDisplayName
        }
        guard name.count <= maxDisplayNameLength else {
            throw TrainingEnvironmentAuthoringError.displayNameTooLong(maxDisplayNameLength)
        }
        guard manifest.description.count <= maxDescriptionLength else {
            throw TrainingEnvironmentAuthoringError.descriptionTooLong(maxDescriptionLength)
        }
        let trimmedID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw TrainingEnvironmentValidationError.emptyID }
        guard trimmedID.range(of: TrainingEnvironmentValidator.idPattern, options: .regularExpression) != nil else {
            throw TrainingEnvironmentValidationError.invalidIDCharacters
        }
        try validateAnchor(manifest.defaultSpawn, label: "Start")
        try validateAnchor(manifest.defaultGoal, label: "Goal")
        guard manifest.obstacles.count <= TrainingEnvironmentObstacleRecord.maxCount else {
            throw TrainingEnvironmentAuthoringError.tooManyObstacles(TrainingEnvironmentObstacleRecord.maxCount)
        }
    }

    static func validateForSave(manifest: TrainingEnvironmentManifest, packageRoot: URL) throws {
        try validateManifest(manifest)
        try TrainingEnvironmentValidator.validate(manifest: manifest, packageRoot: packageRoot)
    }

    private static func validateAnchor(_ pose: TrainingEnvironmentPose, label: String) throws {
        for (value, axis) in [(pose.xM, "X"), (pose.yM, "Y"), (pose.zM, "Z")] {
            guard value.isFinite, abs(value) <= maxAnchorAbsM else {
                throw TrainingEnvironmentAuthoringError.anchorOutOfRange(label: label, axis: axis, limitM: maxAnchorAbsM)
            }
        }
        guard pose.yawDeg.isFinite, abs(pose.yawDeg) <= 360.0 else {
            throw TrainingEnvironmentAuthoringError.invalidYaw(label: label)
        }
    }
}

enum TrainingEnvironmentAuthoringError: LocalizedError, Equatable {
    case emptyDisplayName
    case displayNameTooLong(Int)
    case descriptionTooLong(Int)
    case anchorOutOfRange(label: String, axis: String, limitM: Double)
    case invalidYaw(label: String)
    case bundledReadOnly
    case missingTemplateWorld
    case tooManyObstacles(Int)

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "Enter a display name before saving."
        case .displayNameTooLong(let max):
            return "Display name must be at most \(max) characters."
        case .descriptionTooLong(let max):
            return "Description must be at most \(max) characters."
        case .anchorOutOfRange(let label, let axis, let limit):
            return "\(label) \(axis) must be within ±\(Int(limit)) m."
        case .invalidYaw(let label):
            return "\(label) heading must be a finite angle in degrees."
        case .bundledReadOnly:
            return "Bundled environments cannot be edited. Duplicate as a new world to customize."
        case .missingTemplateWorld:
            return "No template world file is available to create a new environment."
        case .tooManyObstacles(let max):
            return "This world has more than \(max) obstacles. Remove some before saving."
        }
    }
}
