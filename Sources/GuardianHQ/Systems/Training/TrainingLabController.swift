import Combine
import Foundation
import SwiftUI

/// Unified Training lab controller — teaching session + formation follow (merged façade).
@MainActor
final class TrainingLabController: ObservableObject {
    let teaching: TrainingPanelController
    let formation: FormationsPlaygroundController

    private weak var roster: TrainingLabRosterController?
    private var cancellables = Set<AnyCancellable>()

    init() {
        teaching = TrainingPanelController()
        formation = FormationsPlaygroundController()
        forwardObjectWillChange(from: teaching)
        forwardObjectWillChange(from: formation)
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
    }

    func bindRoster(_ roster: TrainingLabRosterController) {
        self.roster = roster
    }

    func mapSessionContext(roster: TrainingLabRosterController) -> TrainingLabMapSessionContext? {
        guard let fleetLink = teaching.fleetLinkForMapSession,
              let sitl = teaching.sitlForMapSession
        else { return nil }
        let learningSquad = roster.learningSquad
        let singleVehicleStart: TrainingTaskPose? =
            learningSquad?.isSingleVehicle == true ? teaching.taskLayout?.start : nil
        return TrainingLabMapSessionContext(
            fleetLink: fleetLink,
            sitl: sitl,
            gazebo: teaching.gazeboForMapSession,
            spawnDefaults: teaching.spawnDefaultsForMapSession,
            simulationPlatform: teaching.simulationPlatformForMapSession,
            activeGazeboWorldID: teaching.activeGazeboWorldID,
            environment: teaching.selectedEnvironment,
            squads: roster.squads,
            learningSquadID: roster.learningSquadID ?? roster.squads.first?.id,
            learningSquadSingleVehicleStart: singleVehicleStart
        )
    }

    func resetMap(roster: TrainingLabRosterController) async {
        guard let context = mapSessionContext(roster: roster) else { return }
        await TrainingLabMapSessionLifecycle.resetMap(context: context)
    }

    func buildMap(roster: TrainingLabRosterController) async {
        guard let context = mapSessionContext(roster: roster) else { return }
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

    private func forwardObjectWillChange(from object: some ObservableObject) {
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
