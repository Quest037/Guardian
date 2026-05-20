import Foundation
import SwiftUI

/// Training lab vehicle squads — spawn, retry, replace, and drag-and-drop roster editing.
@MainActor
final class TrainingLabRosterController: ObservableObject {
    @Published private(set) var squads: [TrainingLabSquad] = []
    /// Squad in focus for teach / promote (defaults to Alpha / first squad).
    @Published var learningSquadID: UUID?
    /// Squad selected on the training map for formation edit (blue outline + drag).
    @Published var mapSelectedSquadID: UUID?
    @Published private(set) var isBusy = false
    /// Bumps when squad roster links or zone anchors change so the Gazebo viewport refreshes formation slots.
    @Published private(set) var formationViewportTick = UUID()

    private weak var lab: TrainingLabController?
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

    /// Squads with at least one linked simulator (excludes persisted shells awaiting reconnect).
    var squadsWithLinkedSimulators: [TrainingLabSquad] {
        squads.filter(\.hasLinkedSimulator)
    }

    var canAddAnotherSquad: Bool {
        squads.count < TrainingLabRosterLimits.maxSquads
    }

    func canAddWingman(to squadID: UUID) -> Bool {
        guard let squad = squad(id: squadID) else { return false }
        return squad.vehicleCount < TrainingLabRosterLimits.maxVehiclesPerSquad
    }

    var showLearningSquadPicker: Bool {
        squadsWithLinkedSimulators.count > 1
    }

    func attach(
        lab: TrainingLabController,
        fleetLink: FleetLinkService,
        missionControl: MissionControlStore,
        simulationPlatform: SimulationPlatform
    ) {
        self.lab = lab
        training = lab.teaching
        playground = lab.formation
        self.fleetLink = fleetLink
        self.missionControl = missionControl
        self.simulationPlatform = simulationPlatform
        lab.formation.onTrainingSimulatorLinkReady = { [weak self] vehicleID in
            guard let self, let lab = self.lab else { return }
            guard let entryID = self.entryID(forVehicleID: vehicleID) else { return }
            await lab.positionVehicleAtStartSlot(roster: self, entryID: entryID)
        }
        restorePersistedDraftIfNeeded()
    }

    func restorePersistedDraftIfNeeded() {
        guard squads.isEmpty else { return }
        guard let snapshot = try? TrainingLabRosterStore.load() else { return }
        squads = TrainingLabRosterStore.squads(from: snapshot)
        learningSquadID = snapshot.learningSquadID
        reconcileRosterLinksAfterRestore()
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

    /// Map + Vehicles rail card selection for formation edit (independent of learning squad).
    func selectMapSquad(_ squadID: UUID) {
        guard squads.contains(where: { $0.id == squadID }) else { return }
        mapSelectedSquadID = squadID
        markFormationViewportDirty()
    }

    /// Toggle map selection for a squad (MCS-style blue outline on primary slots).
    func toggleMapSquadSelection(_ squadID: UUID) {
        guard squads.contains(where: { $0.id == squadID }) else { return }
        if mapSelectedSquadID == squadID {
            mapSelectedSquadID = nil
        } else {
            selectMapSquad(squadID)
        }
    }

    func clearMapSquadSelection() {
        guard mapSelectedSquadID != nil else { return }
        mapSelectedSquadID = nil
        markFormationViewportDirty()
    }

    private func pruneMapSelectionIfSquadRemoved() {
        guard let id = mapSelectedSquadID else { return }
        guard squads.contains(where: { $0.id == id }) else {
            mapSelectedSquadID = nil
            markFormationViewportDirty()
            return
        }
    }

    func clampLearningSquadSelection() {
        learningSquadID = TrainingLabLearningSquadSelection.clampedLearningSquadID(
            current: learningSquadID,
            squads: squads
        )
    }

    func refreshSlotStatesFromFleet(stripFailedLinks: Bool = true) {
        guard let playground else { return }
        for squadIndex in squads.indices {
            refreshEntry(&squads[squadIndex].primary, playground: playground)
            for wingIndex in squads[squadIndex].wingmen.indices {
                refreshEntry(&squads[squadIndex].wingmen[wingIndex], playground: playground)
            }
        }
        if stripFailedLinks {
            stripUnlinkedEntries()
        }
        compactEmptySquads()
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
    }

    private func refreshEntry(
        _ entry: inout TrainingLabRosterEntry,
        playground: FormationsPlaygroundController
    ) {
        guard let vehicleID = entry.vehicleID else { return }
        if let match = playground.slots.first(where: { $0.vehicleID == vehicleID }) {
            entry.slotState = match
            entry.restoredLinkVehicleID = nil
        }
    }

    /// Drops persisted shells that did not reconnect to a live training SITL row.
    private func reconcileRosterLinksAfterRestore() {
        refreshSlotStatesFromFleet(stripFailedLinks: false)
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
    }

    private func stripUnlinkedEntries() {
        for index in squads.indices {
            squads[index].wingmen.removeAll { !$0.hasLinkedSimulator }
        }
        squads.removeAll { !$0.hasLinkedSimulator }
    }

    func syncPlaygroundSlots() {
        playground?.replaceSlotsForTrainingLab(allSlotStates)
        markFormationViewportDirty()
    }

    func markFormationViewportDirty() {
        formationViewportTick = UUID()
    }

    func syncTrainingFromLearningSquad() {
        guard let training, let squad = learningSquad else {
            training?.clearRosterPrimarySlot()
            return
        }
        training.applyLearningSquadContext(
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

        let (squad, squadIndex, entryIndex): (TrainingLabSquad, Int, Int)
        if let squadID, let idx = squads.firstIndex(where: { $0.id == squadID }) {
            squad = squads[idx]
            squadIndex = idx
            entryIndex = squad.wingmen.count + 1
        } else {
            squad = TrainingLabSquad(primary: entry)
            squadIndex = squads.count
            entryIndex = 0
        }
        let spawnBundle = training.spawnAlignmentForPendingEntry(
            squad: squad,
            squadIndex: squadIndex,
            entryIndex: entryIndex,
            learningSquadID: learningSquadID
        )
        let sitlDefaults = spawnBundle?.sitlDefaults ?? training.spawnDefaultsForMapSession
        let gazeboPlacement = spawnBundle?.gazeboPlacement

        isBusy = true
        let slot = await playground.spawnTrainingLabSimulator(
            preset: preset,
            platform: simulationPlatform,
            sizeTier: sizeTier,
            sitlSpawnDefaults: sitlDefaults,
            gazeboPlacement: gazeboPlacement,
            missionControl: missionControl
        )
        isBusy = false
        guard let slot else { return }

        var linked = entry
        linked.slotState = slot
        linked.restoredLinkVehicleID = nil

        if let squadID, let squadIndex = squads.firstIndex(where: { $0.id == squadID }) {
            guard squads[squadIndex].vehicleCount < TrainingLabRosterLimits.maxVehiclesPerSquad else {
                training.showOperatorToast(
                    "This squad is full (\(TrainingLabRosterLimits.maxVehiclesPerSquad) vehicles max).",
                    style: .warning
                )
                return
            }
            squads[squadIndex].wingmen.append(linked)
            squads[squadIndex] = squads[squadIndex]
        } else {
            guard squads.count < TrainingLabRosterLimits.maxSquads else {
                training.showOperatorToast(
                    "Squad limit reached (\(TrainingLabRosterLimits.maxSquads) squads max).",
                    style: .warning
                )
                return
            }
            squads.append(TrainingLabSquad(primary: linked))
            if learningSquadID == nil {
                learningSquadID = squads.last?.id
            }
        }
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
        markFormationViewportDirty()
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

        let entryIndex = location.isPrimary ? 0 : location.wingIndex + 1
        let spawnBundle = training.spawnAlignmentForPendingEntry(
            squad: location.squad,
            squadIndex: location.squadIndex,
            entryIndex: entryIndex,
            learningSquadID: learningSquadID
        )

        let replacement = await playground.replaceSlot(
            slotID: slotID,
            missionControl: missionControl,
            preset: location.entry.vehicleClass.simulationPreset,
            platform: simulationPlatform,
            sizeTier: location.entry.vehicleSizeTier,
            sitlSpawnDefaults: spawnBundle?.sitlDefaults,
            gazeboPlacement: spawnBundle?.gazeboPlacement
        )

        guard let replacement else { return }
        setEntrySlot(entryID: entryID, slot: replacement)
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
        markFormationViewportDirty()
    }

    func absorbPrimaryIntoSquad(draggedEntryID: UUID, targetSquadID: UUID) {
        guard canAddWingman(to: targetSquadID) else {
            training?.showOperatorToast(
                "This squad is full (\(TrainingLabRosterLimits.maxVehiclesPerSquad) vehicles max).",
                style: .warning
            )
            return
        }
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
        markFormationViewportDirty()
    }

    /// Moves a wingman onto another squad (drop on that squad's primary or any wingman card).
    func moveWingmanToSquad(entryID: UUID, targetSquadID: UUID) {
        guard canAddWingman(to: targetSquadID) else {
            training?.showOperatorToast(
                "This squad is full (\(TrainingLabRosterLimits.maxVehiclesPerSquad) vehicles max).",
                style: .warning
            )
            return
        }
        guard TrainingLabRosterEditing.moveWingmanToSquad(
            squads: &squads,
            entryID: entryID,
            targetSquadID: targetSquadID
        ) else { return }
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
        markFormationViewportDirty()
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
        guard squads.count < TrainingLabRosterLimits.maxSquads else {
            training?.showOperatorToast(
                "Squad limit reached (\(TrainingLabRosterLimits.maxSquads) squads max).",
                style: .warning
            )
            return
        }
        guard let source = entryLocation(entryID: entryID), !source.isPrimary else { return }
        let wingman = squads[source.squadIndex].wingmen.remove(at: source.wingIndex)
        squads.append(TrainingLabSquad(primary: wingman))
        clampLearningSquadSelection()
        syncPlaygroundSlots()
        syncTrainingFromLearningSquad()
        persistRoster()
        markFormationViewportDirty()
    }

    func squadIndex(for squadID: UUID) -> Int? {
        squads.firstIndex(where: { $0.id == squadID })
    }

    func squad(id: UUID) -> TrainingLabSquad? {
        squads.first(where: { $0.id == id })
    }

    private func anchorClusteredAtZoneCenter(
        _ anchor: TrainingLabZoneFormationAnchor?,
        zone: WorldBuilderZoneState
    ) -> Bool {
        guard let anchor, zone.placed else { return false }
        let epsilonM = 0.75
        return abs(anchor.centerXM - zone.centerXM) < epsilonM
            && abs(anchor.centerYM - zone.centerYM) < epsilonM
    }

    func updateFormationPolicy(squadID: UUID, policy: TrainingLabSquadFormationPolicy) {
        guard let index = squads.firstIndex(where: { $0.id == squadID }) else { return }
        squads[index].formationPolicy = policy
        persistRoster()
        markFormationViewportDirty()
    }

    /// Seeds missing start/end anchors; respreads squads still parked on the zone centre (legacy bundles).
    func ensureZoneFormationAnchors(zones: WorldBuilderZonesSnapshot) {
        var changed = false
        for index in squads.indices where squads[index].vehicleCount > 0 {
            if zones.start.placed {
                if squads[index].startZoneAnchor == nil {
                    squads[index].startZoneAnchor = .defaultForSquadIndex(index, in: zones.start)
                    changed = true
                } else if index > 0, anchorClusteredAtZoneCenter(squads[index].startZoneAnchor, zone: zones.start) {
                    squads[index].startZoneAnchor = .defaultForSquadIndex(index, in: zones.start)
                    changed = true
                }
            }
            if zones.end.placed {
                if squads[index].endZoneAnchor == nil {
                    squads[index].endZoneAnchor = .defaultForSquadIndex(index, in: zones.end)
                    changed = true
                } else if index > 0, anchorClusteredAtZoneCenter(squads[index].endZoneAnchor, zone: zones.end) {
                    squads[index].endZoneAnchor = .defaultForSquadIndex(index, in: zones.end)
                    changed = true
                }
            }
        }
        if changed {
            persistRoster()
            markFormationViewportDirty()
        }
    }

    @discardableResult
    func updateZoneFormationAnchor(
        squadID: UUID,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        centerXM: Double,
        centerYM: Double,
        headingDeg: Double,
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) -> Bool {
        guard let index = squads.firstIndex(where: { $0.id == squadID }) else { return false }
        let zone = phase == .start ? zones.start : zones.end
        guard zone.placed else { return false }
        let proposed = TrainingLabZoneFormationAnchor(
            centerXM: centerXM,
            centerYM: centerYM,
            headingDeg: headingDeg
        )
        let prior: TrainingLabZoneFormationAnchor? = switch phase {
        case .start: squads[index].startZoneAnchor
        case .end: squads[index].endZoneAnchor
        }
        let resolved = TrainingLabFormationSlotPlacement.resolveAnchorAfterMapDrag(
            proposed: proposed,
            prior: prior,
            squad: squads[index],
            squadIndex: index,
            phase: phase,
            squads: squads,
            zones: zones,
            mapHalfExtentM: mapHalfExtentM
        )
        switch phase {
        case .start:
            squads[index].startZoneAnchor = resolved.anchor
        case .end:
            squads[index].endZoneAnchor = resolved.anchor
        }
        persistRoster()
        return resolved.adjustedFromDrop
    }

    @discardableResult
    func rotateZoneFormationHeading(
        squadID: UUID,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        deltaDeg: Double,
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) -> Bool {
        guard let index = squads.firstIndex(where: { $0.id == squadID }) else { return false }
        let zone = phase == .start ? zones.start : zones.end
        guard zone.placed else { return false }
        var anchor: TrainingLabZoneFormationAnchor = switch phase {
        case .start:
            squads[index].startZoneAnchor ?? .defaultForSquadIndex(index, in: zone)
        case .end:
            squads[index].endZoneAnchor ?? .defaultForSquadIndex(index, in: zone)
        }
        var heading = anchor.headingDeg + deltaDeg
        while heading < 0 { heading += 360 }
        while heading >= 360 { heading -= 360 }
        anchor.headingDeg = heading
        let snapped = updateZoneFormationAnchor(
            squadID: squadID,
            phase: phase,
            centerXM: anchor.centerXM,
            centerYM: anchor.centerYM,
            headingDeg: anchor.headingDeg,
            zones: zones,
            mapHalfExtentM: mapHalfExtentM
        )
        markFormationViewportDirty()
        return snapped
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
        markFormationViewportDirty()
    }

    func entryID(forVehicleID vehicleID: String) -> UUID? {
        for squad in squads {
            if squad.primary.slotState?.vehicleID == vehicleID {
                return squad.primary.id
            }
            if let wing = squad.wingmen.first(where: { $0.slotState?.vehicleID == vehicleID }) {
                return wing.id
            }
        }
        return nil
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
        location.entry.restoredLinkVehicleID = nil
        if location.isPrimary {
            squads[location.squadIndex].primary = location.entry
        } else {
            squads[location.squadIndex].wingmen[location.wingIndex] = location.entry
        }
    }

    private func compactEmptySquads() {
        squads.removeAll { $0.allEntries.allSatisfy { $0.vehicleID == nil } }
        pruneMapSelectionIfSquadRemoved()
    }

    func clearRoster() {
        squads = []
        learningSquadID = nil
        mapSelectedSquadID = nil
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
