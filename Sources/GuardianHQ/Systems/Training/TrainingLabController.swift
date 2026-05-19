import Combine
import Foundation
import SwiftUI

/// Unified Training lab controller — teaching session + formation follow (merged façade).
@MainActor
final class TrainingLabController: ObservableObject {
    let teaching: TrainingPanelController
    let formation: FormationsPlaygroundController

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
