import Foundation

/// Last-selected training environment per task kind (Application Support).
enum TrainingEnvironmentSelectionStore {
    private static let fileName = "training_environment_selection.json"

    struct Selections: Codable, Equatable, Sendable {
        var byTaskKind: [String: String] = [:]
        var byTaskKindAndVehicleClass: [String: String] = [:]
    }

    static func load(fileURL: URL? = nil) throws -> Selections {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return Selections() }
        return try JSONDecoder().decode(Selections.self, from: data)
    }

    static func save(_ selections: Selections, fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let data = try JSONEncoder().encode(selections)
        try data.write(to: url, options: .atomic)
    }

    static func selectedEnvironmentID(
        task: TrainingTaskKind,
        vehicleClass: TrainingVehicleClass? = nil,
        fileURL: URL? = nil
    ) throws -> String? {
        let all = try load(fileURL: fileURL)
        if let vehicleClass {
            let key = compositeKey(task: task, vehicleClass: vehicleClass)
            if let id = all.byTaskKindAndVehicleClass[key] { return id }
        }
        return all.byTaskKind[task.rawValue]
    }

    /// Drops any persisted selection that pointed at a removed environment package.
    static func removeReferences(to environmentID: String, fileURL: URL? = nil) throws {
        var all = try load(fileURL: fileURL)
        all.byTaskKind = all.byTaskKind.filter { $0.value != environmentID }
        all.byTaskKindAndVehicleClass = all.byTaskKindAndVehicleClass.filter { $0.value != environmentID }
        try save(all, fileURL: fileURL)
    }

    static func setSelectedEnvironmentID(
        _ environmentID: String?,
        task: TrainingTaskKind,
        vehicleClass: TrainingVehicleClass? = nil,
        fileURL: URL? = nil
    ) throws {
        var all = try load(fileURL: fileURL)
        if let environmentID {
            all.byTaskKind[task.rawValue] = environmentID
            if let vehicleClass {
                all.byTaskKindAndVehicleClass[compositeKey(task: task, vehicleClass: vehicleClass)] = environmentID
            }
        } else {
            all.byTaskKind.removeValue(forKey: task.rawValue)
            if let vehicleClass {
                all.byTaskKindAndVehicleClass.removeValue(forKey: compositeKey(task: task, vehicleClass: vehicleClass))
            }
        }
        try save(all, fileURL: fileURL)
    }

    private static func compositeKey(task: TrainingTaskKind, vehicleClass: TrainingVehicleClass) -> String {
        "\(task.rawValue)|\(vehicleClass.rawValue)"
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingEnvironmentSelectionStore", code: 1)
        }
        let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
