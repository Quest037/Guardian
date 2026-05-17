import Combine
import Darwin
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
    private var nextSimulationInstance: Int = 0

    init() {
        GuardianAppQuitCoordinator.shared.noteSitlServiceCreated(self)
    }

    func attachFleetLink(_ link: FleetLinkService) {
        fleetLink = link
    }

    private func reconcileFleetLinkVehicleCacheAfterSitlChange() {
        if instances.isEmpty {
            nextSimulationInstance = 0
        }
        guard let link = fleetLink else { return }
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

    private func reserveNextSimulationInstance(maxScan: Int = 256) -> Int? {
        var candidate = instances.isEmpty ? 0 : max(0, nextSimulationInstance)
        let occupied = Set(instances.map(\.stackInstanceIndex))
        for _ in 0..<maxScan {
            if !occupied.contains(candidate) {
                nextSimulationInstance = candidate + 1
                return candidate
            }
            candidate += 1
        }
        return nil
    }

    func stopAll() {
        stopAllForApplicationQuit()
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Terminate every SITL child (PX4 / ArduPilot) and stop all MAVSDK sessions on the fleet link. Does not run stale-cache reconcile (used from app quit after fleet teardown).
    func stopAllForApplicationQuit() {
        for id in Array(runners.keys) {
            if let runner = runners.removeValue(forKey: id) {
                runner.onLogLine = nil
                runner.onTerminated = nil
                runner.stop()
            }
        }
        runners.removeAll()
        instances.removeAll()
        lastError = nil
        nextSimulationInstance = 0
        fleetLink?.stopAllVehicleSessions()
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
        let systemID = instances[idx].stackInstanceIndex + 1
        fleetLink?.unregisterSimulatedVehicle(systemID: systemID)
        instances.removeAll { $0.id == id }
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Removes a finished instance row from the list.
    func dismiss(id: UUID) {
        instances.removeAll { $0.id == id && !$0.isAlive }
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Running built-in SITL session id for a Guardian sim stream key (`sysid:n`), when the process is alive.
    func sitlSessionID(forGuardianVehicleID vehicleID: String) -> UUID? {
        let prefix = "sysid:"
        guard vehicleID.hasPrefix(prefix) else { return nil }
        let rest = String(vehicleID.dropFirst(prefix.count))
        guard let systemID = Int(rest), systemID >= 1 else { return nil }
        let stackIndex = systemID - 1
        return instances.first(where: { $0.isAlive && $0.stackInstanceIndex == stackIndex })?.id
    }

    /// Restarts Guardian's MAVSDK session to a running built-in SITL without stopping the sim process.
    @discardableResult
    func reconnectFleetLink(
        sitlSessionID: UUID,
        spawnDefaults: SimSpawnDefaults? = nil
    ) async -> Bool {
        lastError = nil
        guard let link = fleetLink else {
            lastError = "Fleet link is not attached."
            return false
        }
        guard let inst = instances.first(where: { $0.id == sitlSessionID && $0.isAlive }) else {
            lastError = "Simulator is not running."
            return false
        }
        return await reconnectFleetLink(instance: inst, link: link, spawnDefaults: spawnDefaults)
    }

    /// Restarts the MAVSDK session for a Guardian-managed sim stream (`sysid:n`).
    @discardableResult
    func reconnectFleetLink(
        forGuardianVehicleID vehicleID: String,
        spawnDefaults: SimSpawnDefaults? = nil
    ) async -> Bool {
        lastError = nil
        guard let sessionID = sitlSessionID(forGuardianVehicleID: vehicleID) else {
            lastError = "No running simulator matches this vehicle."
            return false
        }
        return await reconnectFleetLink(sitlSessionID: sessionID, spawnDefaults: spawnDefaults)
    }

    private func reconnectFleetLink(
        instance inst: SitlRunningInstance,
        link: FleetLinkService,
        spawnDefaults: SimSpawnDefaults?
    ) async -> Bool {
        let stackIndex = inst.stackInstanceIndex
        let systemID = stackIndex + 1
        let mavlinkURL: String
        let stack: FleetAutopilotStack
        switch inst.platform {
        case .ardupilot:
            mavlinkURL = "udpin://0.0.0.0:\(SitlLaunchRecipe.ardupilotMavproxyOutPort(instance: stackIndex))"
            stack = .ardupilot
        case .px4:
            mavlinkURL = "udpin://0.0.0.0:\(SitlLaunchRecipe.px4OffboardRemotePort(instance: stackIndex))"
            stack = .px4
        }
        link.appendSimulationLog(
            "Reconnecting MAVSDK link [vehicle=\(inst.preset.displayName) instance=\(stackIndex) mavlink_sysid=\(systemID) session=\(inst.id.uuidString)] \(mavlinkURL)"
        )
        let ok = await link.reconnectSimulatedVehicleSession(
            systemID: systemID,
            mavlinkConnectionURL: mavlinkURL,
            autopilotStack: stack,
            vehicleType: inst.preset.fleetVehicleType,
            spawnDefaults: spawnDefaults
        )
        if !ok, lastError == nil {
            lastError = link.lastError ?? "Reconnect failed."
        }
        return ok
    }

    /// Spawns SITL when **Simulate** is on.
    func spawn(preset: SimulationVehiclePreset, platform: SimulationPlatform, defaults: SimSpawnDefaults) {
        lastError = nil
        guard let link = fleetLink, link.isSimulateEnabled else {
            lastError = "Turn on Simulate before spawning SITL."
            return
        }

        switch platform {
        case .ardupilot:
            spawnArduPilot(preset: preset, link: link, defaults: defaults)
        case .px4:
            spawnPX4(preset: preset, link: link, defaults: defaults)
        }
    }

    private func spawnArduPilot(preset: SimulationVehiclePreset, link: FleetLinkService, defaults: SimSpawnDefaults) {
        guard let root = SitlLaunchRecipe.ardupilotRootPath() else {
            lastError = SitlError.missingArduPilotRuntime.errorDescription
            return
        }

        guard let instance = reserveNextSimulationInstance() else {
            lastError = "No available simulation instance slot found."
            return
        }

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.arduPilotSpec(root: root, preset: preset, instance: instance, spawnDefaults: defaults)
        } catch {
            lastError = error.localizedDescription
            return
        }

        if !SitlLaunchRecipe.pythonHasPexpectForSitl() {
            lastError =
                "Python module 'pexpect' is missing (ArduPilot sim_vehicle needs it). From the Guardian repo run: make sitl-deps"
            return
        }

        if !SitlLaunchRecipe.pythonHasEmpyForSitl() {
            lastError =
                "Python package 'empy' is missing (ArduPilot waf needs it: import em). Run: make sitl-deps — or: pip3 install empy==3.3.4"
            return
        }

        if !SitlLaunchRecipe.mavproxyLikelyAvailable(environment: spec.environment) {
            lastError = "MAVProxy is not on PATH (looked for mavproxy.py). Install with: pip3 install MAVProxy — then retry."
            return
        }

        if !SitlLaunchRecipe.pythonHasGnureadlineForMavproxy() {
            lastError =
                "Python module 'gnureadline' is missing (MAVProxy needs it on macOS). Run: make sitl-deps — or: pip3 install gnureadline"
            return
        }

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
            link.updateSimulationLifecycleFromSitlLog(systemID: instance + 1, line: line)
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
            link?.unregisterSimulatedVehicle(systemID: instance + 1)
            link?.appendSimulationLog(
                "SITL exited [platform=ArduPilot instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] code=\(code)"
            )
            self.reconcileFleetLinkVehicleCacheAfterSitlChange()
        }

        do {
            try runner.start(spec: spec)
            runners[id] = runner
            let mavsdkIngressPort = SitlLaunchRecipe.ardupilotMavproxyOutPort(instance: instance)
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
            link.registerSimulatedVehicle(
                systemID: instance + 1,
                mavlinkConnectionURL: "udpin://0.0.0.0:\(mavsdkIngressPort)",
                autopilotStack: .ardupilot,
                vehicleType: preset.fleetVehicleType,
                spawnDefaults: defaults
            )
            link.appendSimulationLog(
                "Started ArduPilot SITL [vehicle=\(preset.displayName) instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] primary_link=\(mavsdkIngressPort)"
            )
        } catch {
            lastError = error.localizedDescription
            runner.onLogLine = nil
            runner.onTerminated = nil
        }
    }

    private func spawnPX4(preset: SimulationVehiclePreset, link: FleetLinkService, defaults: SimSpawnDefaults) {
        guard let root = SitlLaunchRecipe.px4SitlRootPath() else {
            lastError = SitlError.missingPx4AutopilotRoot.errorDescription
            return
        }

        guard let instance = reserveNextAvailablePx4Instance() else {
            lastError = "No available PX4 SITL instance slot found (ports busy). Stop existing PX4 sims and retry."
            return
        }

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.px4Spec(root: root, preset: preset, instance: instance, spawnDefaults: defaults)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let gcsUdpPort = SitlLaunchRecipe.px4SihGcsUdpPort(instance: instance)
        let mavsdkIngressPort = SitlLaunchRecipe.px4OffboardRemotePort(instance: instance)

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
            link.updateSimulationLifecycleFromSitlLog(systemID: instance + 1, line: line)
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
            link?.unregisterSimulatedVehicle(systemID: instance + 1)
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
            link.registerSimulatedVehicle(
                systemID: instance + 1,
                mavlinkConnectionURL: "udpin://0.0.0.0:\(mavsdkIngressPort)",
                autopilotStack: .px4,
                vehicleType: preset.fleetVehicleType,
                spawnDefaults: defaults
            )
            link.appendSimulationLog(
                "Started PX4 SITL [sim=SIH vehicle=\(preset.displayName) model=\(preset.px4SitlSimModel()) instance=\(instance) mavlink_sysid=\(instance + 1) session=\(id.uuidString)] gcs_udp=\(gcsUdpPort) mavsdk_udpin=\(mavsdkIngressPort)"
            )
        } catch {
            lastError = error.localizedDescription
            runner.onLogLine = nil
            runner.onTerminated = nil
        }
    }

    /// Finds the next PX4 instance whose GCS UDP port is not currently occupied.
    private func reserveNextAvailablePx4Instance(maxScan: Int = 64) -> Int? {
        var candidate = instances.isEmpty ? 0 : max(0, nextSimulationInstance)
        let occupiedByGuardian = Set(instances.map(\.stackInstanceIndex))
        for _ in 0..<maxScan {
            let gcsPort = SitlLaunchRecipe.px4SihGcsUdpPort(instance: candidate)
            if !occupiedByGuardian.contains(candidate), isUdpPortBindable(gcsPort) {
                nextSimulationInstance = candidate + 1
                return candidate
            }
            candidate += 1
        }
        return nil
    }

    /// True when we can bind to the UDP port now (best-effort conflict probe).
    private func isUdpPortBindable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
        return ok
    }

    /// Inserts a running SITL row so ``resolvedFleetStreamVehicleID`` resolves without spawning (tests only).
    func seedMissionRunTestSitlRunningInstance(
        id: UUID,
        stackInstanceIndex: Int = 0,
        platform: SimulationPlatform = .px4,
        preset: SimulationVehiclePreset = .uavMultirotor
    ) {
        instances.append(
            SitlRunningInstance(
                id: id,
                platform: platform,
                preset: preset,
                stackInstanceIndex: stackInstanceIndex,
                isAlive: true,
                lastExitCode: nil
            )
        )
    }
}
