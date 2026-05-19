import Foundation

/// Resolved autonomy brain for a training task kind + vehicle class on one Mission Control run.
struct MissionRunBrainBinding: Codable, Equatable, Hashable, Sendable, Identifiable {
    var taskKindRaw: String
    var vehicleClassRaw: String
    var brainId: UUID
    var brainVersion: GuardianBrainVersion
    var displayName: String

    var id: String { "\(taskKindRaw)|\(vehicleClassRaw)" }

    init(
        taskKindRaw: String,
        vehicleClassRaw: String,
        brainId: UUID,
        brainVersion: GuardianBrainVersion,
        displayName: String
    ) {
        self.taskKindRaw = taskKindRaw
        self.vehicleClassRaw = vehicleClassRaw
        self.brainId = brainId
        self.brainVersion = brainVersion
        self.displayName = displayName
    }

    init(manifest: GuardianBrainPackManifest) {
        self.init(
            taskKindRaw: manifest.taskKinds.first ?? "",
            vehicleClassRaw: manifest.vehicleClasses.first ?? "",
            brainId: manifest.brainId,
            brainVersion: manifest.brainVersion,
            displayName: manifest.displayName
        )
    }
}
