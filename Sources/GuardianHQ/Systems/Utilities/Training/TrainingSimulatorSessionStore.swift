import Foundation

/// Persists the training panel's tracked SITL session across tab changes (Application Support).
enum TrainingSimulatorSessionStore {
    private static let fileName = "training_simulator_session.json"

    struct Record: Codable, Equatable, Sendable {
        var sitlSessionID: UUID
    }

    static func load(fileURL: URL? = nil) throws -> Record? {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    static func save(_ sessionID: UUID, fileURL: URL? = nil) throws {
        try save(Record(sitlSessionID: sessionID), fileURL: fileURL)
    }

    static func save(_ record: Record, fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    static func clear(fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingSimulatorSessionStore", code: 1)
        }
        let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
