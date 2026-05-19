import Foundation

struct GuardianBrainPinKey: Codable, Hashable, Sendable {
    var taskKindRaw: String
    var vehicleClassRaw: String
}

struct GuardianBrainPinRecord: Codable, Equatable, Sendable {
    var brainId: UUID
    var brainVersion: GuardianBrainVersion
    var displayName: String
}

/// Operator-pinned default brain per training task kind + vehicle class (Mission catalogue).
enum GuardianBrainPinDefaultsStore {
    private static let fileName = "brain_pin_defaults.json"

    static func loadAll(fileURL: URL? = nil) throws -> [GuardianBrainPinKey: GuardianBrainPinRecord] {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        let rows = try JSONDecoder().decode([GuardianBrainPinRow].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.record) })
    }

    static func saveAll(_ pins: [GuardianBrainPinKey: GuardianBrainPinRecord], fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let rows = pins.map { GuardianBrainPinRow(key: $0.key, record: $0.value) }
            .sorted { lhs, rhs in
                if lhs.key.vehicleClassRaw != rhs.key.vehicleClassRaw {
                    return lhs.key.vehicleClassRaw < rhs.key.vehicleClassRaw
                }
                return lhs.key.taskKindRaw < rhs.key.taskKindRaw
            }
        let data = try JSONEncoder().encode(rows)
        try data.write(to: url, options: .atomic)
    }

    static func pin(manifest: GuardianBrainPackManifest, fileURL: URL? = nil) throws {
        guard let taskKind = manifest.taskKinds.first,
              let vehicleClass = manifest.vehicleClasses.first else {
            throw GuardianBrainPackError.importFailed("Pack manifest must include task and vehicle class tags.")
        }
        var pins = try loadAll(fileURL: fileURL)
        let key = GuardianBrainPinKey(taskKindRaw: taskKind, vehicleClassRaw: vehicleClass)
        pins[key] = GuardianBrainPinRecord(
            brainId: manifest.brainId,
            brainVersion: manifest.brainVersion,
            displayName: manifest.displayName
        )
        try saveAll(pins, fileURL: fileURL)
    }

    static func unpinnedRecord(
        taskKindRaw: String,
        vehicleClassRaw: String,
        fileURL: URL? = nil
    ) throws -> GuardianBrainPinRecord? {
        let key = GuardianBrainPinKey(taskKindRaw: taskKindRaw, vehicleClassRaw: vehicleClassRaw)
        return try loadAll(fileURL: fileURL)[key]
    }

    static func isPinned(entry: GuardianBrainCatalogueEntry, fileURL: URL? = nil) throws -> Bool {
        guard let taskKind = entry.manifest.taskKinds.first,
              let vehicleClass = entry.manifest.vehicleClasses.first else { return false }
        guard let pin = try unpinnedRecord(taskKindRaw: taskKind, vehicleClassRaw: vehicleClass, fileURL: fileURL) else {
            return false
        }
        return pin.brainId == entry.manifest.brainId && pin.brainVersion == entry.manifest.brainVersion
    }

    /// Seeds run bindings from pinned defaults (one row per pin key).
    static func missionRunBindings(fileURL: URL? = nil) throws -> [MissionRunBrainBinding] {
        try loadAll(fileURL: fileURL).map { key, record in
            MissionRunBrainBinding(
                taskKindRaw: key.taskKindRaw,
                vehicleClassRaw: key.vehicleClassRaw,
                brainId: record.brainId,
                brainVersion: record.brainVersion,
                displayName: record.displayName
            )
        }
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw GuardianBrainPackError.importFailed("Application Support is unavailable.")
        }
        let dir = base.appendingPathComponent("Guardian/brains", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private struct GuardianBrainPinRow: Codable {
        var key: GuardianBrainPinKey
        var record: GuardianBrainPinRecord
    }
}
