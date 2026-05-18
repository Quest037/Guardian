import Foundation

/// Persists the training panel target slot across tab changes (Application Support).
enum TrainingTargetSlotStore {
    private static let fileName = "training_target_slot.json"

    static func load(fileURL: URL? = nil) throws -> TrainingTaskPose? {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try JSONDecoder().decode(TrainingTaskPose.self, from: data)
    }

    static func save(_ pose: TrainingTaskPose, fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let data = try JSONEncoder().encode(pose)
        try data.write(to: url, options: .atomic)
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingTargetSlotStore", code: 1)
        }
        let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
