import Combine
import Foundation

/// One spawned SITL process tracked in the UI.
struct SitlRunningInstance: Identifiable, Equatable {
    let id: UUID
    let platform: SimulationPlatform
    let preset: SimulationVehiclePreset
    /// ArduPilot `sim_vehicle.py -I` index, or PX4 `px4 -i` instance id.
    let stackInstanceIndex: Int
    var isAlive: Bool
    var lastExitCode: Int32?
}

/// Spawns and supervises built-in SITL processes. Logs are forwarded into `FleetLinkService` via `attachFleetLink`.
@MainActor
final class SitlService: ObservableObject {
    @Published private(set) var instances: [SitlRunningInstance] = []
    @Published private(set) var lastError: String?

    weak var fleetLink: FleetLinkService?

    private var runners: [UUID: SitlProcessRunner] = [:]
    private var nextArduPilotInstance: Int = 0
    private var nextPx4Instance: Int = 0

    func attachFleetLink(_ link: FleetLinkService) {
        fleetLink = link
    }

    /// After any SITL inventory change, clear MAVSDK’s stale “first vehicle” snapshot when nothing is alive and Simulate is on.
    private func reconcileFleetLinkVehicleCacheAfterSitlChange() {
        guard let link = fleetLink, link.isSimulateEnabled else { return }
        link.setTrackedSystemIDs(activeSystemIDs())
        let anyAlive = instances.contains { $0.isAlive }
        if !anyAlive {
            link.clearStaleVehicleStateWhenNoSitlAlive()
        }
    }

    private func activeSystemIDs() -> Set<Int> {
        Set(
            instances
                .filter { $0.isAlive }
                .map { $0.stackInstanceIndex + 1 }
        )
    }

    func stopAll() {
        for id in runners.keys {
            if let runner = runners.removeValue(forKey: id) {
                runner.onLogLine = nil
                runner.onTerminated = nil
                runner.stop()
            }
        }
        instances.removeAll()
        lastError = nil
        fleetLink?.setTrackedSystemIDs([])
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Stops a running SITL process and removes its row.
    func stop(id: UUID) {
        guard let idx = instances.firstIndex(where: { $0.id == id }), instances[idx].isAlive else {
            dismiss(id: id)
            return
        }
        if let runner = runners.removeValue(forKey: id) {
            runner.onLogLine = nil
            runner.onTerminated = nil
            runner.stop()
        }
        instances.removeAll { $0.id == id }
        fleetLink?.setTrackedSystemIDs(activeSystemIDs())
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Removes a finished instance row from the list.
    func dismiss(id: UUID) {
        instances.removeAll { $0.id == id && !$0.isAlive }
    }

    /// Spawns SITL when **Simulate** is on and the link server is running.
    func spawn(preset: SimulationVehiclePreset, platform: SimulationPlatform) {
        lastError = nil
        guard let link = fleetLink, link.isRunning, link.isSimulateEnabled else {
            lastError = "Turn on Server and Simulate before spawning SITL."
            return
        }

        switch platform {
        case .ardupilot:
            spawnArduPilot(preset: preset, link: link)
        case .px4:
            spawnPX4(preset: preset, link: link)
        }
    }

    private func spawnArduPilot(preset: SimulationVehiclePreset, link: FleetLinkService) {
        guard let root = SitlLaunchRecipe.ardupilotRootPath() else {
            lastError = SitlError.missingArduPilotRuntime.errorDescription
            return
        }

        let instance = nextArduPilotInstance
        nextArduPilotInstance += 1

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.arduPilotSpec(root: root, preset: preset, instance: instance)
        } catch {
            lastError = error.localizedDescription
            nextArduPilotInstance -= 1
            return
        }

        if !SitlLaunchRecipe.pythonHasPexpectForSitl() {
            lastError =
                "Python module 'pexpect' is missing (ArduPilot sim_vehicle needs it). From the Guardian repo run: make sitl-deps"
            nextArduPilotInstance -= 1
            return
        }

        if !SitlLaunchRecipe.pythonHasEmpyForSitl() {
            lastError =
                "Python package 'empy' is missing (ArduPilot waf needs it: import em). Run: make sitl-deps — or: pip3 install empy==3.3.4"
            nextArduPilotInstance -= 1
            return
        }

        if !SitlLaunchRecipe.mavproxyLikelyAvailable(environment: spec.environment) {
            lastError = "MAVProxy is not on PATH (looked for mavproxy.py). Install with: pip3 install MAVProxy — then retry."
            nextArduPilotInstance -= 1
            return
        }

        if !SitlLaunchRecipe.pythonHasGnureadlineForMavproxy() {
            lastError =
                "Python module 'gnureadline' is missing (MAVProxy needs it on macOS). Run: make sitl-deps — or: pip3 install gnureadline"
            nextArduPilotInstance -= 1
            return
        }

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
        }
        runner.onTerminated = { [weak self, weak link] code in
            guard let self else { return }
            self.runners.removeValue(forKey: id)
            if let idx = self.instances.firstIndex(where: { $0.id == id }) {
                var row = self.instances[idx]
                row.isAlive = false
                row.lastExitCode = code
                self.instances[idx] = row
            }
            link?.appendSimulationLog(
                "SITL exited [platform=ArduPilot instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] code=\(code)"
            )
            self.reconcileFleetLinkVehicleCacheAfterSitlChange()
        }

        do {
            try runner.start(spec: spec)
            runners[id] = runner
            instances.append(
                SitlRunningInstance(
                    id: id,
                    platform: .ardupilot,
                    preset: preset,
                    stackInstanceIndex: instance,
                    isAlive: true,
                    lastExitCode: nil
                )
            )
            link.setTrackedSystemIDs(activeSystemIDs())
            link.appendSimulationLog(
                "Started ArduPilot SITL [vehicle=\(preset.displayName) instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] primary_link=14550"
            )
        } catch {
            lastError = error.localizedDescription
            nextArduPilotInstance -= 1
            runner.onLogLine = nil
            runner.onTerminated = nil
        }
    }

    private func spawnPX4(preset: SimulationVehiclePreset, link: FleetLinkService) {
        guard let root = SitlLaunchRecipe.px4SitlRootPath() else {
            lastError = SitlError.missingPx4AutopilotRoot.errorDescription
            return
        }

        let instance = nextPx4Instance
        nextPx4Instance += 1

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.px4Spec(root: root, preset: preset, instance: instance)
        } catch {
            lastError = error.localizedDescription
            nextPx4Instance -= 1
            return
        }

        let mavlinkPort = SitlLaunchRecipe.px4SihGcsUdpPort(instance: instance)

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
        }
        runner.onTerminated = { [weak self, weak link] code in
            guard let self else { return }
            self.runners.removeValue(forKey: id)
            if let idx = self.instances.firstIndex(where: { $0.id == id }) {
                var row = self.instances[idx]
                row.isAlive = false
                row.lastExitCode = code
                self.instances[idx] = row
            }
            link?.appendSimulationLog(
                "SITL exited [platform=PX4 instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] code=\(code)"
            )
            self.reconcileFleetLinkVehicleCacheAfterSitlChange()
        }

        do {
            try runner.start(spec: spec)
            runners[id] = runner
            instances.append(
                SitlRunningInstance(
                    id: id,
                    platform: .px4,
                    preset: preset,
                    stackInstanceIndex: instance,
                    isAlive: true,
                    lastExitCode: nil
                )
            )
            link.setTrackedSystemIDs(activeSystemIDs())
            link.appendSimulationLog(
                "Started PX4 SITL [sim=SIH vehicle=\(preset.displayName) model=\(preset.px4SitlSimModel()) instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] gcs_udp=\(mavlinkPort) mavsdk_udpout=auto"
            )
        } catch {
            lastError = error.localizedDescription
            nextPx4Instance -= 1
            runner.onLogLine = nil
            runner.onTerminated = nil
        }
    }
}
