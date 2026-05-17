import Foundation

/// One planner decision — retained for playground logs, unit tests, and future MRE / assistant tooling.
struct GuardianMovementEvidenceRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var timestamp: Date
    var vehicleType: FleetVehicleType
    var selectedMovementID: GuardianMovementID
    var alongErrorM: Double
    var signedLateralErrorM: Double
    var distToSlotM: Double
    var bodyForwardMS: Double
    var yawspeedDegS: Double
    var summary: String
    var declinedMovementIDs: [GuardianMovementID]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        vehicleType: FleetVehicleType,
        plan: GuardianMovementPursuitPlan,
        context: GuardianMovementSlotApproachContext,
        declinedMovementIDs: [GuardianMovementID] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.vehicleType = vehicleType
        self.selectedMovementID = plan.movementID
        self.alongErrorM = context.alongErrorM
        self.signedLateralErrorM = context.signedLateralErrorM
        self.distToSlotM = context.distToSlotM
        self.bodyForwardMS = plan.bodyForwardMS
        self.yawspeedDegS = plan.yawspeedDegS
        self.summary = plan.summary
        self.declinedMovementIDs = declinedMovementIDs
    }
}

/// Append-only store for formation-lab / test evidence (JSON file under Application Support in app; in-memory in tests).
enum GuardianMovementEvidenceStore {
    private static let fileName = "guardian_movement_evidence.jsonl"

    static func append(_ record: GuardianMovementEvidenceRecord, fileURL: URL? = nil) throws {
        let url = try fileURL ?? defaultFileURL()
        let line = try JSONEncoder().encode(record)
        var data = (try? Data(contentsOf: url)) ?? Data()
        if !data.isEmpty { data.append(0x0A) }
        data.append(line)
        try data.write(to: url, options: .atomic)
    }

    static func loadAll(fileURL: URL? = nil) throws -> [GuardianMovementEvidenceRecord] {
        let url = try fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        var out: [GuardianMovementEvidenceRecord] = []
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let rec = try? decoder.decode(GuardianMovementEvidenceRecord.self, from: line) {
                out.append(rec)
            }
        }
        return out
    }

    static func defaultFileURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { throw NSError(domain: "GuardianMovementEvidenceStore", code: 1) }
        let dir = base.appendingPathComponent("Guardian/movements", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
