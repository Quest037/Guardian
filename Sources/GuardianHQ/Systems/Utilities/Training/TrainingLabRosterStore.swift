import Foundation

/// Persisted Training lab vehicle squads (draft roster + per-squad formation policy).
enum TrainingLabRosterStore {
    private static let fileName = "training_lab_roster.json"

    struct PersistedEntry: Codable, Equatable, Sendable {
        var vehicleClass: TrainingVehicleClass
        var vehicleSizeTier: VehicleSizeTier
    }

    struct PersistedSquad: Codable, Equatable, Sendable {
        var id: UUID
        var primary: PersistedEntry
        var wingmen: [PersistedEntry]
        var taskKind: TrainingTaskKind
        var formationPolicy: TrainingLabSquadFormationPolicy

        init(
            id: UUID,
            primary: PersistedEntry,
            wingmen: [PersistedEntry],
            taskKind: TrainingTaskKind = .reverseIntoSlot,
            formationPolicy: TrainingLabSquadFormationPolicy
        ) {
            self.id = id
            self.primary = primary
            self.wingmen = wingmen
            self.taskKind = taskKind
            self.formationPolicy = formationPolicy
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            primary = try container.decode(PersistedEntry.self, forKey: .primary)
            wingmen = try container.decode([PersistedEntry].self, forKey: .wingmen)
            taskKind = try container.decodeIfPresent(TrainingTaskKind.self, forKey: .taskKind) ?? .reverseIntoSlot
            formationPolicy = try container.decode(TrainingLabSquadFormationPolicy.self, forKey: .formationPolicy)
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
        Snapshot(
            squads: squads.map { squad in
                PersistedSquad(
                    id: squad.id,
                    primary: PersistedEntry(
                        vehicleClass: squad.primary.vehicleClass,
                        vehicleSizeTier: squad.primary.vehicleSizeTier
                    ),
                    wingmen: squad.wingmen.map {
                        PersistedEntry(vehicleClass: $0.vehicleClass, vehicleSizeTier: $0.vehicleSizeTier)
                    },
                    taskKind: squad.taskKind,
                    formationPolicy: squad.formationPolicy
                )
            },
            learningSquadID: learningSquadID
        )
    }

    static func squads(from snapshot: Snapshot) -> [TrainingLabSquad] {
        snapshot.squads.map { row in
            TrainingLabSquad(
                id: row.id,
                primary: TrainingLabRosterEntry(
                    vehicleClass: row.primary.vehicleClass,
                    vehicleSizeTier: row.primary.vehicleSizeTier
                ),
                wingmen: row.wingmen.map {
                    TrainingLabRosterEntry(vehicleClass: $0.vehicleClass, vehicleSizeTier: $0.vehicleSizeTier)
                },
                taskKind: row.taskKind,
                formationPolicy: row.formationPolicy
            )
        }
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
