import Foundation
import SwiftUI

/// Training lab vehicle squads — spawn, retry, replace, and drag-and-drop roster editing.
@MainActor
final class TrainingLabRosterController: ObservableObject {
    @Published private(set) var squads: [TrainingLabSquad] = []
    /// Squad whose skill task is in focus for teach / promote (defaults to Alpha / first squad).
    @Published var learningSquadID: UUID?
    @Published private(set) var isBusy = false

    private weak var training: TrainingPanelController?
    private weak var playground: FormationsPlaygroundController?
    private weak var fleetLink: FleetLinkService?
    private weak var missionControl: MissionControlStore?
    private var simulationPlatform: SimulationPlatform = .ardupilot

    var totalVehicleCount: Int {
        squads.reduce(0) { $0 + $1.allEntries.count }
    }

    var usesMultiVehicleFormation: Bool {
        totalVehicleCount > 1
    }

    var learningSquadIndex: Int? {
        guard let learningSquadID else { return squads.isEmpty ? nil : 0 }
        return squads.firstIndex(where: { $0.id == learningSquadID })
    }

    var learningSquad: TrainingLabSquad? {
        guard let index = learningSquadIndex else { return nil }
        return squads[index]
    }

    /// Learning squad has a primary plus wingmen — run formation control for that squad's vehicles.
    var learningSquadUsesFormation: Bool {
        guard let squad = learningSquad else { return false }
        return !squad.isSingleVehicle
    }

    func isLearningSquad(_ squadID: UUID) -> Bool {
        learningSquadID == squadID || (learningSquadID == nil && squads.first?.id == squadID)
    }

    var allSlotStates: [FormationsPlaygroundSlotState] {
        squads.flatMap { $0.allEntries.compactMap(\.slotState) }
    }

    func attach(
        lab: TrainingLabController,
        fleetLink: FleetLinkService,
        missionControl: MissionControlStore,
        simulationPlatform: SimulationPlatform
    ) {
        training = lab.teaching
        playground = lab.formation
        self.fleetLink = fleetLink
        self.missionControl = missionControl
        self.simulationPlatform = simulationPlatform
        restorePersistedDraftIfNeeded()
    }

    func restorePersistedDraftIfNeeded() {
        guard squads.isEmpty else { return }
        guard let snapshot = try? TrainingLabRosterStore.load() else { return }
        squads = TrainingLabRosterStore.squads(from: snapshot)
        learningSquadID = snapshot.learningSquadID
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
    }

    func persistRoster() {
        let snapshot = TrainingLabRosterStore.snapshot(from: squads, learningSquadID: learningSquadID)
        try? TrainingLabRosterStore.save(snapshot)
    }

    func setLearningSquad(id: UUID) {
        guard squads.contains(where: { $0.id == id }) else { return }
        learningSquadID = id
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    func updateTaskKind(squadID: UUID, taskKind: TrainingTaskKind) {
        guard let index = squads.firstIndex(where: { $0.id == squadID }) else { return }
        squads[index].taskKind = taskKind
        if isLearningSquad(squadID) {
            syncTrainingFromLearningSquad()
        }
        persistRoster()
    }

    func clampLearningSquadSelection() {
        learningSquadID = TrainingLabLearningSquadSelection.clampedLearningSquadID(
            current: learningSquadID,
            squads: squads
        )
    }

    func refreshSlotStatesFromFleet() {
        guard let fleetLink, let playground else { return }
        for squadIndex in squads.indices {
            refreshEntry(&squads[squadIndex].primary, fleetLink: fleetLink, playground: playground)
            for wingIndex in squads[squadIndex].wingmen.indices {
                refreshEntry(&squads[squadIndex].wingmen[wingIndex], fleetLink: fleetLink, playground: playground)
            }
        }
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
    }

    private func refreshEntry(
        _ entry: inout TrainingLabRosterEntry,
        fleetLink: FleetLinkService,
        playground: FormationsPlaygroundController
    ) {
        guard let vehicleID = entry.vehicleID else { return }
        if let match = playground.slots.first(where: { $0.vehicleID == vehicleID }) {
            entry.slotState = match
        }
    }

    func syncPlaygroundSlots() {
        playground?.replaceSlotsForTrainingLab(allSlotStates)
    }

    func syncTrainingFromLearningSquad() {
        guard let training, let squad = learningSquad else {
            training?.clearRosterPrimarySlot()
            return
        }
        training.applyLearningSquadContext(
            taskKind: squad.taskKind,
            vehicleClass: squad.primary.vehicleClass,
            vehicleSizeTier: squad.primary.vehicleSizeTier,
            primarySlot: squad.isSingleVehicle ? squad.primary.slotState : nil
        )
    }

    /// Spawn a simulator and attach it as a new primary squad or wingman (unlimited roster size).
    func addVehicle(
        preset: SimulationVehiclePreset,
        sizeTier: VehicleSizeTier,
        wingmanTo squadID: UUID?
    ) async {
        guard let training, let playground, let missionControl, let fleetLink else { return }
        guard fleetLink.isSimulateEnabled else { return }
        guard let vehicleClass = TrainingVehicleClass.fromSimulationPreset(preset) else { return }

        guard await training.ensureGazeboRunWorldIfAlive() else { return }

        let entry = TrainingLabRosterEntry(
            vehicleClass: vehicleClass,
            vehicleSizeTier: sizeTier
        )

        isBusy = true
        let slot = await playground.spawnTrainingLabSimulator(
            preset: preset,
            platform: simulationPlatform,
            sizeTier: sizeTier,
            gazeboPlacement: training.trainingGazeboPlacementForSpawn(),
            missionControl: missionControl
        )
        isBusy = false
        guard let slot else { return }

        var linked = entry
        linked.slotState = slot

        if let squadID, let squadIndex = squads.firstIndex(where: { $0.id == squadID }) {
            squads[squadIndex].wingmen.append(linked)
        } else {
            squads.append(TrainingLabSquad(primary: linked))
            if learningSquadID == nil {
                learningSquadID = squads.last?.id
            }
        }
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    func addPrimaryVehicle(
        preset: SimulationVehiclePreset,
        sizeTier: VehicleSizeTier
    ) async {
        await addVehicle(preset: preset, sizeTier: sizeTier, wingmanTo: nil)
    }

    func addWingman(to squadID: UUID, preset: SimulationVehiclePreset, sizeTier: VehicleSizeTier) async {
        await addVehicle(preset: preset, sizeTier: sizeTier, wingmanTo: squadID)
    }

    func retryVehicle(entryID: UUID) async {
        guard let missionControl, let playground else { return }
        guard let location = entryLocation(entryID: entryID),
              let slotID = location.entry.slotState?.id
        else { return }

        if learningSquadUsesFormation || usesMultiVehicleFormation {
            await playground.retrySimulatorConnection(slotID: slotID, missionControl: missionControl)
        } else if let training {
            await training.retrySimulatorConnection(missionControl: missionControl)
        }
        refreshSlotStatesFromFleet()
    }

    /// Stop + spawn a fresh SITL in the same roster row (slot id may change).
    func replaceVehicle(entryID: UUID) async {
        guard let training, let playground, let missionControl else { return }
        guard let location = entryLocation(entryID: entryID),
              let slotID = location.entry.slotState?.id
        else { return }

        isBusy = true
        defer { isBusy = false }

        guard await training.ensureGazeboRunWorldIfAlive() else { return }

        let replacement = await playground.replaceSlot(
            slotID: slotID,
            missionControl: missionControl,
            preset: location.entry.vehicleClass.simulationPreset,
            platform: simulationPlatform,
            sizeTier: location.entry.vehicleSizeTier,
            gazeboPlacement: training.trainingGazeboPlacementForSpawn()
        )

        guard let replacement else { return }
        setEntrySlot(entryID: entryID, slot: replacement)
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    func absorbPrimaryIntoSquad(draggedEntryID: UUID, targetSquadID: UUID) {
        guard TrainingLabRosterEditing.absorbPrimaryIntoSquad(
            squads: &squads,
            draggedEntryID: draggedEntryID,
            targetSquadID: targetSquadID
        ) else { return }
        clampLearningSquadSelection()
        compactEmptySquads()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    /// Moves a wingman onto another squad (drop on that squad's primary or any wingman card).
    func moveWingmanToSquad(entryID: UUID, targetSquadID: UUID) {
        guard TrainingLabRosterEditing.moveWingmanToSquad(
            squads: &squads,
            entryID: entryID,
            targetSquadID: targetSquadID
        ) else { return }
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    /// Re-runs preflight on a linked simulator row (Training lab cards).
    func retryPreflight(entryID: UUID) async {
        guard let missionControl, let playground else { return }
        guard let location = entryLocation(entryID: entryID),
              let slotID = location.entry.slotState?.id
        else { return }
        await playground.retrySimulatorConnection(slotID: slotID, missionControl: missionControl)
        refreshSlotStatesFromFleet()
    }

    func promoteWingmanToNewSquad(entryID: UUID) {
        guard let source = entryLocation(entryID: entryID), !source.isPrimary else { return }
        let wingman = squads[source.squadIndex].wingmen.remove(at: source.wingIndex)
        squads.append(TrainingLabSquad(primary: wingman))
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    func squadIndex(for squadID: UUID) -> Int? {
        squads.firstIndex(where: { $0.id == squadID })
    }

    func squad(id: UUID) -> TrainingLabSquad? {
        squads.first(where: { $0.id == id })
    }

    func updateFormationPolicy(squadID: UUID, policy: TrainingLabSquadFormationPolicy) {
        guard let index = squads.firstIndex(where: { $0.id == squadID }) else { return }
        squads[index].formationPolicy = policy
        persistRoster()
    }

    /// Stops the simulator and removes one roster row; promotes a wingman if the primary is removed.
    func removeVehicle(entryID: UUID) async {
        guard let playground else { return }
        guard let location = entryLocation(entryID: entryID),
              let slotID = location.entry.slotState?.id
        else { return }

        await playground.removeSlot(id: slotID)

        if location.isPrimary {
            if squads[location.squadIndex].wingmen.isEmpty {
                squads.remove(at: location.squadIndex)
            } else {
                let promoted = squads[location.squadIndex].wingmen.removeFirst()
                squads[location.squadIndex].primary = promoted
            }
        } else {
            squads[location.squadIndex].wingmen.remove(at: location.wingIndex)
        }

        clampLearningSquadSelection()
        compactEmptySquads()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }

    func entryLocation(entryID: UUID) -> (squadIndex: Int, squad: TrainingLabSquad, isPrimary: Bool, wingIndex: Int, entry: TrainingLabRosterEntry)? {
        for (index, squad) in squads.enumerated() {
            if squad.primary.id == entryID {
                return (index, squad, true, 0, squad.primary)
            }
            if let wingIndex = squad.wingmen.firstIndex(where: { $0.id == entryID }) {
                return (index, squad, false, wingIndex, squad.wingmen[wingIndex])
            }
        }
        return nil
    }

    private func setEntrySlot(entryID: UUID, slot: FormationsPlaygroundSlotState) {
        guard var location = entryLocation(entryID: entryID) else { return }
        location.entry.slotState = slot
        if location.isPrimary {
            squads[location.squadIndex].primary = location.entry
        } else {
            squads[location.squadIndex].wingmen[location.wingIndex] = location.entry
        }
    }

    private func compactEmptySquads() {
        squads.removeAll { $0.allEntries.allSatisfy { $0.slotState == nil } }
    }

    func clearRoster() {
        squads = []
        learningSquadID = nil
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
    }
}

extension TrainingVehicleClass {
    static func fromSimulationPreset(_ preset: SimulationVehiclePreset) -> TrainingVehicleClass? {
        switch preset {
        case .uavMultirotor: return .uavCopter
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        case .ugvLegged: return .ugvWheeled
        case .uavFixedWing, .uavVTOL, .usv, .uuv: return nil
        }
    }
}
