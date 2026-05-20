import Foundation

/// Persisted Training lab vehicle squads (draft roster + per-squad formation policy).
enum TrainingLabRosterStore {
    private static let fileName = "training_lab_roster.json"

    struct PersistedEntry: Codable, Equatable, Sendable {
        var vehicleClass: TrainingVehicleClass
        var vehicleSizeTier: VehicleSizeTier
        /// Live simulator row; omitted in older snapshots (those squads are not restored).
        var vehicleID: String?
    }

    struct PersistedSquad: Codable, Equatable, Sendable {
        var id: UUID
        var primary: PersistedEntry
        var wingmen: [PersistedEntry]
        var taskKind: TrainingTaskKind
        var formationPolicy: TrainingLabSquadFormationPolicy
        var startZoneAnchor: TrainingLabZoneFormationAnchor?
        var endZoneAnchor: TrainingLabZoneFormationAnchor?

        init(
            id: UUID,
            primary: PersistedEntry,
            wingmen: [PersistedEntry],
            taskKind: TrainingTaskKind = .reverseIntoSlot,
            formationPolicy: TrainingLabSquadFormationPolicy,
            startZoneAnchor: TrainingLabZoneFormationAnchor? = nil,
            endZoneAnchor: TrainingLabZoneFormationAnchor? = nil
        ) {
            self.id = id
            self.primary = primary
            self.wingmen = wingmen
            self.taskKind = taskKind
            self.formationPolicy = formationPolicy
            self.startZoneAnchor = startZoneAnchor
            self.endZoneAnchor = endZoneAnchor
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            primary = try container.decode(PersistedEntry.self, forKey: .primary)
            wingmen = try container.decode([PersistedEntry].self, forKey: .wingmen)
            taskKind = try container.decodeIfPresent(TrainingTaskKind.self, forKey: .taskKind) ?? .reverseIntoSlot
            formationPolicy = try container.decode(TrainingLabSquadFormationPolicy.self, forKey: .formationPolicy)
            startZoneAnchor = try container.decodeIfPresent(TrainingLabZoneFormationAnchor.self, forKey: .startZoneAnchor)
            endZoneAnchor = try container.decodeIfPresent(TrainingLabZoneFormationAnchor.self, forKey: .endZoneAnchor)
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        var squads: [PersistedSquad] = []
        /// Squad receiving skill teaching / promotion focus (defaults to Alpha / first squad when nil on load).
        var learningSquadID: UUID?
    }

    static func load(fileURL: URL? = nil) throws -> Snapshot {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return Snapshot() }
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot, fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func snapshot(from squads: [TrainingLabSquad], learningSquadID: UUID?) -> Snapshot {
        let persistedSquads: [PersistedSquad] = squads.compactMap { squad in
            guard let primary = persistedEntry(from: squad.primary) else { return nil }
            let wingmen = squad.wingmen.compactMap { persistedEntry(from: $0) }
            return PersistedSquad(
                id: squad.id,
                primary: primary,
                wingmen: wingmen,
                taskKind: squad.taskKind,
                formationPolicy: squad.formationPolicy,
                startZoneAnchor: squad.startZoneAnchor,
                endZoneAnchor: squad.endZoneAnchor
            )
        }
        let clampedLearningID: UUID? = {
            guard let learningSquadID, persistedSquads.contains(where: { $0.id == learningSquadID }) else {
                return persistedSquads.first?.id
            }
            return learningSquadID
        }()
        return Snapshot(squads: persistedSquads, learningSquadID: clampedLearningID)
    }

    static func squads(from snapshot: Snapshot) -> [TrainingLabSquad] {
        snapshot.squads.compactMap { row in
            guard let primary = rosterEntry(from: row.primary) else { return nil }
            let wingmen = row.wingmen.compactMap { rosterEntry(from: $0) }
            return TrainingLabSquad(
                id: row.id,
                primary: primary,
                wingmen: wingmen,
                taskKind: row.taskKind,
                formationPolicy: row.formationPolicy,
                startZoneAnchor: row.startZoneAnchor,
                endZoneAnchor: row.endZoneAnchor
            )
        }
    }

    private static func persistedEntry(from entry: TrainingLabRosterEntry) -> PersistedEntry? {
        guard let vehicleID = entry.vehicleID else { return nil }
        return PersistedEntry(
            vehicleClass: entry.vehicleClass,
            vehicleSizeTier: entry.vehicleSizeTier,
            vehicleID: vehicleID
        )
    }

    private static func rosterEntry(from persisted: PersistedEntry) -> TrainingLabRosterEntry? {
        guard let vehicleID = persisted.vehicleID, !vehicleID.isEmpty else { return nil }
        return TrainingLabRosterEntry(
            restoredLinkVehicleID: vehicleID,
            vehicleClass: persisted.vehicleClass,
            vehicleSizeTier: persisted.vehicleSizeTier
        )
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingLabRosterStore", code: 1)
        }
        let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
