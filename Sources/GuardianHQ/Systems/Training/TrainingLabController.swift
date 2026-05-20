import Combine
import Foundation
import SwiftUI

/// Unified Training lab controller — one product surface; teaching and formation follow are implementation façades (squad of 1 for teach, wingmen for multi-vehicle formation).
@MainActor
final class TrainingLabController: ObservableObject {
    let teaching: TrainingPanelController
    let formation: FormationsPlaygroundController
    let run: TrainingLabRunOrchestrator

    private weak var roster: TrainingLabRosterController?
    private var cancellables = Set<AnyCancellable>()

    /// Invoked after a transit run publishes its result and **before** ``resetMap`` restores start poses.
    /// Use for metrics, teaching evidence, or exports — hub telemetry and route progress are still valid.
    var onTransitRunWillResetMap: (@MainActor (TrainingLabRunCompletionSnapshot) async -> Void)?

    /// Fired when ``TrainingLabRunOrchestrator/transitRouteOverlays`` is updated (push into gzweb viewport).
    var onTransitRouteOverlaysDidChange: (@MainActor () -> Void)?

    init() {
        teaching = TrainingPanelController()
        formation = FormationsPlaygroundController()
        run = TrainingLabRunOrchestrator()
        forwardObjectWillChange(from: teaching)
        forwardObjectWillChange(from: formation)
        forwardObjectWillChange(from: run)
        run.bind(lab: self)
    }

    func attach(
        fleetLink: FleetLinkService,
        sitl: SitlService,
        spawnDefaults: SimSpawnDefaults,
        simulationPlatform: SimulationPlatform,
        gazebo: GazeboService? = nil,
        requiresGazeboRunWorld: Bool = false,
        toastCenter: ToastCenter? = nil
    ) {
        teaching.attach(
            fleetLink: fleetLink,
            sitl: sitl,
            spawnDefaults: spawnDefaults,
            simulationPlatform: simulationPlatform,
            gazebo: gazebo,
            requiresGazeboRunWorld: requiresGazeboRunWorld,
            toastCenter: toastCenter
        )
        formation.attach(
            fleetLink: fleetLink,
            sitl: sitl,
            spawnDefaults: spawnDefaults,
            simulationPlatform: simulationPlatform
        )
        teaching.onMapEnvironmentWillChange = { [weak self] in
            guard let self, let roster = self.roster else { return }
            Task { await self.resetMap(roster: roster) }
        }
        teaching.onMapEnvironmentSelected = { [weak self] in
            self?.refreshFormationMapSessionGeodeticOrigin()
        }
        refreshFormationMapSessionGeodeticOrigin()
    }

    func refreshFormationMapSessionGeodeticOrigin() {
        formation.applyMapSessionSpawnDefaults(teaching.mapSessionGeodeticOrigin())
    }

    func bindRoster(_ roster: TrainingLabRosterController) {
        self.roster = roster
    }

    func mapSessionContext(
        roster: TrainingLabRosterController,
        log: TrainingLabMapSessionDiagnostics.LogHandler? = nil
    ) -> TrainingLabMapSessionContext? {
        guard let fleetLink = teaching.fleetLinkForMapSession,
              let sitl = teaching.sitlForMapSession
        else { return nil }
        let learningSquad = roster.learningSquad
        let environment = teaching.selectedEnvironment
        let spawnDefaults = teaching.spawnDefaultsForMapSession
        let mapGeodeticOrigin = environment.map {
            TrainingLabMapSessionLifecycle.mapGeodeticOrigin(
                environment: $0,
                spawnDefaults: spawnDefaults
            )
        } ?? spawnDefaults
        let zonesConfigured = environment?.manifest.hasConfiguredStartAndEndZones == true
        let singleVehicleStart: TrainingTaskPose? =
            (!zonesConfigured && learningSquad?.isSingleVehicle == true)
            ? teaching.taskLayout?.start
            : nil
        return TrainingLabMapSessionContext(
            fleetLink: fleetLink,
            sitl: sitl,
            gazebo: teaching.gazeboForMapSession,
            spawnDefaults: spawnDefaults,
            mapGeodeticOrigin: mapGeodeticOrigin,
            simulationPlatform: teaching.simulationPlatformForMapSession,
            activeGazeboWorldID: teaching.activeGazeboWorldID,
            environment: environment,
            squads: roster.squads,
            learningSquadID: roster.learningSquadID ?? roster.squads.first?.id,
            learningSquadSingleVehicleStart: singleVehicleStart,
            log: log
        )
    }

    /// Teleport one roster vehicle to its start formation slot (after spawn or map edit).
    func positionVehicleAtStartSlot(roster: TrainingLabRosterController, entryID: UUID) async {
        guard let context = mapSessionContext(roster: roster) else { return }
        await TrainingLabMapSessionLifecycle.positionVehicleAtStart(entryID: entryID, context: context)
    }

    /// Metrics hook → default run-log capture → ``resetMap`` (re-runnable lab session).
    func finalizeTransitRun(
        snapshot: TrainingLabRunCompletionSnapshot,
        roster: TrainingLabRosterController,
        appendRunLog: @escaping (String) -> Void
    ) async {
        if let onTransitRunWillResetMap {
            await onTransitRunWillResetMap(snapshot)
        }
        TrainingLabRunMetricsRecorder.record(snapshot, appendLog: appendRunLog)
        appendRunLog("[Map] Run complete — resetting vehicles to start formation.")
        await resetMap(roster: roster, runLog: { appendRunLog($0) })
    }

    func resetMap(
        roster: TrainingLabRosterController,
        runLog: TrainingLabMapSessionDiagnostics.LogHandler? = nil
    ) async {
        guard let context = mapSessionContext(roster: roster, log: runLog) else {
            runLog?("[Map] resetMap: no map session (fleet/sitl missing).")
            return
        }
        await TrainingLabMapSessionLifecycle.resetMap(context: context)
    }

    func buildMap(
        roster: TrainingLabRosterController,
        runLog: TrainingLabMapSessionDiagnostics.LogHandler? = nil
    ) async {
        teaching.reconcileActiveGazeboRunWorldIfNeeded()
        guard let context = mapSessionContext(roster: roster, log: runLog) else {
            runLog?("[Map] buildMap: no map session (fleet/sitl missing).")
            return
        }
        await TrainingLabMapSessionLifecycle.buildMap(context: context)
    }

    /// Apply the designated learning squad's formation policy before starting a multi-vehicle run.
    func applyFormationPolicyForRun(from roster: TrainingLabRosterController) {
        guard let squad = roster.learningSquad else { return }
        let policy = squad.formationPolicy
        formation.formation = policy.startFormation
        formation.spacing = policy.startSpacing
    }

    func applyFormationControl() async {
        await formation.applyFormationControl()
    }

    func stopActiveFormationSession() async {
        await formation.stopActiveFormationSession()
    }

    /// Leaving the Training lab sidebar section: end an active transit run or reset the map session,
    /// stop fleet control streams, persist roster + map selection, and keep the app-wide Gazebo run world warm.
    func leaveLab(roster: TrainingLabRosterController) async {
        if run.isSessionActive {
            await run.stop(roster: roster)
        } else {
            await resetMap(roster: roster)
            await stopActiveFormationSession()
        }
        await stopRosterControlStreams(roster: roster)
        teaching.cancelTeaching()
        teaching.leavePanel()
        formation.leavePanel()
        roster.refreshSlotStatesFromFleet(stripFailedLinks: false)
        roster.persistRoster()
        teaching.persistEnvironmentSelection()
    }

    private func stopRosterControlStreams(roster: TrainingLabRosterController) async {
        guard let fleetLink = teaching.fleetLinkForMapSession else { return }
        for entry in roster.squads.flatMap(\.allEntries) {
            guard let vehicleID = entry.vehicleID else { continue }
            await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        }
    }

    private func forwardObjectWillChange(from object: some ObservableObject) {
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
