import Foundation

/// NATO-style primary squad labels (1st primary → Alpha, 2nd → Beta, …).
enum TrainingLabSquadCallsign {
    private static let labels = ["Alpha", "Beta", "Gamma", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]

    static func primaryLabel(squadIndex: Int) -> String {
        guard squadIndex >= 0, squadIndex < labels.count else {
            return "Squad \(squadIndex + 1)"
        }
        return labels[squadIndex]
    }

    /// Wingman stream label under a primary (e.g. `Alpha:1`).
    static func wingmanLabel(squadIndex: Int, wingmanIndex: Int) -> String {
        "\(primaryLabel(squadIndex: squadIndex)):\(wingmanIndex)"
    }
}

/// One simulator row in the Training lab roster (primary or wingman).
struct TrainingLabRosterEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    var slotState: FormationsPlaygroundSlotState?
    /// Fleet vehicle id saved for restore until ``slotState`` reconnects.
    var restoredLinkVehicleID: String?
    var vehicleClass: TrainingVehicleClass
    var vehicleSizeTier: VehicleSizeTier

    init(
        id: UUID = UUID(),
        slotState: FormationsPlaygroundSlotState? = nil,
        restoredLinkVehicleID: String? = nil,
        vehicleClass: TrainingVehicleClass = .ugvWheeled,
        vehicleSizeTier: VehicleSizeTier = .medium
    ) {
        self.id = id
        self.slotState = slotState
        self.restoredLinkVehicleID = restoredLinkVehicleID
        self.vehicleClass = vehicleClass
        self.vehicleSizeTier = vehicleSizeTier
    }

    var vehicleID: String? { slotState?.vehicleID ?? restoredLinkVehicleID }

    var hasLinkedSimulator: Bool { slotState != nil }
    var playgroundSlotID: UUID? { slotState?.id }
}

/// Primary + wingmen grouping for drag-and-drop squad editing.
/// ``formationPolicy`` is owned by the squad (stable ``id``), not the primary vehicle row.
struct TrainingLabSquad: Identifiable, Equatable, Sendable {
    let id: UUID
    var primary: TrainingLabRosterEntry
    var wingmen: [TrainingLabRosterEntry]
    /// Legacy persisted field; skill task is app-wide on ``TrainingPanelController``, not per squad.
    var taskKind: TrainingTaskKind
    var formationPolicy: TrainingLabSquadFormationPolicy
    /// Start-zone formation group anchor (ENU m); seeded from zone centre when nil.
    var startZoneAnchor: TrainingLabZoneFormationAnchor?
    /// End-zone formation group anchor (ENU m); seeded from zone centre when nil.
    var endZoneAnchor: TrainingLabZoneFormationAnchor?

    init(
        id: UUID = UUID(),
        primary: TrainingLabRosterEntry,
        wingmen: [TrainingLabRosterEntry] = [],
        taskKind: TrainingTaskKind = .reverseIntoSlot,
        formationPolicy: TrainingLabSquadFormationPolicy = .default,
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

    var allEntries: [TrainingLabRosterEntry] {
        [primary] + wingmen
    }

    /// True when this squad is a single vehicle (primary only) — still a squad for product vocabulary.
    var isSingleVehicle: Bool { wingmen.isEmpty }

    var vehicleCount: Int { allEntries.count }

    var hasLinkedSimulator: Bool {
        allEntries.contains(where: \.hasLinkedSimulator)
    }
}

/// Drag payload token (`entryUUID|squadUUID|role`).
enum TrainingLabVehicleDragPayload {
    case primary(entryID: UUID, squadID: UUID)
    case wingman(entryID: UUID, squadID: UUID)

    var entryID: UUID {
        switch self {
        case .primary(let entryID, _), .wingman(let entryID, _): return entryID
        }
    }

    var squadID: UUID {
        switch self {
        case .primary(_, let squadID), .wingman(_, let squadID): return squadID
        }
    }

    var token: String {
        switch self {
        case .primary(let entryID, let squadID):
            return "p|\(entryID.uuidString)|\(squadID.uuidString)"
        case .wingman(let entryID, let squadID):
            return "w|\(entryID.uuidString)|\(squadID.uuidString)"
        }
    }

    static func parse(_ token: String) -> TrainingLabVehicleDragPayload? {
        let parts = token.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let entryID = UUID(uuidString: parts[1]),
              let squadID = UUID(uuidString: parts[2])
        else { return nil }
        switch parts[0] {
        case "p": return .primary(entryID: entryID, squadID: squadID)
        case "w": return .wingman(entryID: entryID, squadID: squadID)
        default: return nil
        }
    }
}

/// Pure squad roster edits for Training lab drag-and-drop (unit-tested).
enum TrainingLabRosterEditing {
    static func absorbPrimaryIntoSquad(
        squads: inout [TrainingLabSquad],
        draggedEntryID: UUID,
        targetSquadID: UUID
    ) -> Bool {
        guard let sourceIndex = squads.firstIndex(where: { $0.primary.id == draggedEntryID }),
              squads[sourceIndex].id != targetSquadID
        else { return false }

        let movedPrimary = squads[sourceIndex].primary
        let remainingWingmen = squads[sourceIndex].wingmen

        if remainingWingmen.isEmpty {
            squads.remove(at: sourceIndex)
        } else {
            squads[sourceIndex].primary = remainingWingmen[0]
            squads[sourceIndex].wingmen = Array(remainingWingmen.dropFirst())
        }

        guard let targetIndex = squads.firstIndex(where: { $0.id == targetSquadID }) else {
            return false
        }
        squads[targetIndex].wingmen.append(movedPrimary)
        return true
    }

    static func moveWingmanToSquad(
        squads: inout [TrainingLabSquad],
        entryID: UUID,
        targetSquadID: UUID
    ) -> Bool {
        guard let sourceIndex = squads.firstIndex(where: { squad in
            squad.wingmen.contains(where: { $0.id == entryID })
        }),
              squads[sourceIndex].id != targetSquadID,
              let wingIndex = squads[sourceIndex].wingmen.firstIndex(where: { $0.id == entryID }),
              let targetIndex = squads.firstIndex(where: { $0.id == targetSquadID })
        else { return false }

        let wingman = squads[sourceIndex].wingmen.remove(at: wingIndex)
        squads[targetIndex].wingmen.append(wingman)
        return true
    }
}
