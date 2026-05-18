import Foundation

/// Persisted promoted skills from the training lab (Application Support).
@MainActor
enum TrainingSkillStore {
    private static let fileName = "trained_vehicle_skills.json"

    static func loadAll(fileURL: URL? = nil) throws -> [TrainedVehicleSkill] {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        return try JSONDecoder().decode([TrainedVehicleSkill].self, from: data)
    }

    static func saveAll(_ skills: [TrainedVehicleSkill], fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let data = try JSONEncoder().encode(skills)
        try data.write(to: url, options: .atomic)
    }

    static func appendPromoted(_ skill: TrainedVehicleSkill, fileURL: URL? = nil) throws {
        var all = try loadAll(fileURL: fileURL)
        all.removeAll {
            $0.taskKind == skill.taskKind && $0.vehicleClass == skill.vehicleClass
        }
        all.append(skill)
        try saveAll(all, fileURL: fileURL)
    }

    static func promoted(
        task: TrainingTaskKind,
        vehicleClass: TrainingVehicleClass,
        fileURL: URL? = nil
    ) throws -> TrainedVehicleSkill? {
        try loadAll(fileURL: fileURL).last {
            $0.taskKind == task && $0.vehicleClass == vehicleClass
        }
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingSkillStore", code: 1)
        }
        let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
