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
    /// UDP port Guardian listens on for this sim (`udpin://0.0.0.0:port`).
    let mavlinkIngressPort: Int
    /// Allocated MAVLink system id; fleet stream key is ``guardianVehicleStreamKey``.
    let mavlinkSystemID: Int
    /// PX4 GCS mavlink local UDP bind (`px4-rc.mavlink`); `nil` for ArduPilot.
    let px4GcsUdpPort: Int?
    var isAlive: Bool
    var lastExitCode: Int32?
}

extension SitlRunningInstance {
    /// Guardian fleet stream key (`sysid:n`) where `n` is ``mavlinkSystemID``.
    var guardianVehicleStreamKey: String { "sysid:\(mavlinkSystemID)" }
}

/// Spawns and supervises built-in SITL processes. Logs are forwarded into `FleetLinkService` via `attachFleetLink`.
@MainActor
final class SitlService: ObservableObject {
    @Published private(set) var instances: [SitlRunningInstance] = []

    @Published private(set) var lastError: String?

    weak var fleetLink: FleetLinkService?

    private var runners: [UUID: SitlProcessRunner] = [:]
    private var nextSimulationInstance: Int = 0
    private var recentlyReleasedUdpPorts: Set<Int> = []
    private var portReleaseSettleTask: Task<Void, Never>?

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
        let aliveSystemIDs = activeSystemIDs()
        link.pruneSimulatedVehicleSessions(exceptAliveSystemIDs: aliveSystemIDs)
        let anyAlive = !aliveSystemIDs.isEmpty
        if !anyAlive {
            link.clearStaleVehicleStateWhenNoSitlAlive()
            GuardianSitlOrphanBlitz.kickoffWhenAllInstancesStopped()
            schedulePortReleaseSettle()
        }
    }

    private func recordReleasedUdpPorts(from instance: SitlRunningInstance) {
        recentlyReleasedUdpPorts.insert(instance.mavlinkIngressPort)
        if let gcs = instance.px4GcsUdpPort {
            recentlyReleasedUdpPorts.insert(gcs)
        }
    }

    private func schedulePortReleaseSettle() {
        guard !SitlLaunchRecipe.usesLegacySitlPorts(), !recentlyReleasedUdpPorts.isEmpty else { return }
        portReleaseSettleTask?.cancel()
        portReleaseSettleTask = Task { [weak self] in
            await self?.waitForRecentlyReleasedPortsToSettle()
        }
    }

    /// Waits for UDP ports from recently stopped sims to become bindable (random-port respawn / bulk MCS spawn).
    func waitForRecentlyReleasedPortsToSettle(timeout: TimeInterval? = nil) async {
        portReleaseSettleTask?.cancel()
        portReleaseSettleTask = nil
        guard !SitlLaunchRecipe.usesLegacySitlPorts() else {
            recentlyReleasedUdpPorts.removeAll()
            return
        }
        let ports = recentlyReleasedUdpPorts
        guard !ports.isEmpty else { return }
        let waitBudget = timeout ?? GuardianSitlPortReleaseSettle.portReleaseSettleTimeout()
        fleetLink?.appendSimulationLog(
            "Waiting for \(ports.count) sim UDP port(s) to release (timeout=\(waitBudget)s)…"
        )
        for port in ports.sorted() {
            let freed = await GuardianUdpPortUtilities.waitForUdpInboundPortBindable(port: port, timeout: waitBudget)
            if !freed {
                fleetLink?.appendSimulationLog("Sim UDP port \(port) still busy after \(waitBudget)s.")
            }
        }
        recentlyReleasedUdpPorts.removeAll()
    }

    private func activeSystemIDs() -> Set<Int> {
        Set(
            instances
                .filter { $0.isAlive }
                .map(\.mavlinkSystemID)
        )
    }

    private struct MavlinkEndpoints {
        let ingressPort: Int
        let systemID: Int
        let px4GcsUdpPort: Int?
    }

    private func occupiedUdpPortsForAllocation() -> Set<Int> {
        var ports = Set(instances.map(\.mavlinkIngressPort))
        for gcs in instances.compactMap(\.px4GcsUdpPort) {
            ports.insert(gcs)
        }
        return ports
    }

    private func allocateMavlinkEndpoints(platform: SimulationPlatform, stackInstance: Int) -> MavlinkEndpoints? {
        let occupiedPorts = occupiedUdpPortsForAllocation()
        let occupiedSystemIDs = activeSystemIDs()

        if SitlLaunchRecipe.usesLegacySitlPorts() {
            let ingressPort: Int
            let px4Gcs: Int?
            switch platform {
            case .ardupilot:
                ingressPort = SitlLaunchRecipe.ardupilotMavproxyOutPort(instance: stackInstance)
                px4Gcs = nil
            case .px4:
                ingressPort = SitlLaunchRecipe.px4OffboardRemotePort(instance: stackInstance)
                px4Gcs = SitlLaunchRecipe.px4SihGcsUdpPort(instance: stackInstance)
            }
            let systemID = stackInstance + 1
            guard !occupiedSystemIDs.contains(systemID) else { return nil }
            return MavlinkEndpoints(ingressPort: ingressPort, systemID: systemID, px4GcsUdpPort: px4Gcs)
        }

        switch platform {
        case .ardupilot:
            guard let systemID = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkSystemID(occupied: occupiedSystemIDs),
                  let ingressPort = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: occupiedPorts)
            else { return nil }
            return MavlinkEndpoints(ingressPort: ingressPort, systemID: systemID, px4GcsUdpPort: nil)
        case .px4:
            guard let systemID = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkSystemID(occupied: occupiedSystemIDs),
                  let ingressPort = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: occupiedPorts)
            else { return nil }
            var occupiedWithIngress = occupiedPorts
            occupiedWithIngress.insert(ingressPort)
            guard let gcsPort = GuardianSitlMavlinkEndpointAllocator.reserveMavlinkIngressPort(occupied: occupiedWithIngress)
            else { return nil }
            return MavlinkEndpoints(ingressPort: ingressPort, systemID: systemID, px4GcsUdpPort: gcsPort)
        }
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
        for inst in instances {
            recordReleasedUdpPorts(from: inst)
        }
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
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        let inst = instances[idx]
        if !inst.isAlive {
            fleetLink?.unregisterSimulatedVehicle(systemID: inst.mavlinkSystemID)
            instances.removeAll { $0.id == id && !$0.isAlive }
            reconcileFleetLinkVehicleCacheAfterSitlChange()
            return
        }
        recordReleasedUdpPorts(from: inst)
        if let runner = runners.removeValue(forKey: id) {
            runner.onLogLine = nil
            runner.onTerminated = nil
            runner.stop()
        }
        let systemID = inst.mavlinkSystemID
        fleetLink?.unregisterSimulatedVehicle(systemID: systemID)
        instances.removeAll { $0.id == id }
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Removes a finished instance row from the list.
    func dismiss(id: UUID) {
        if let inst = instances.first(where: { $0.id == id && !$0.isAlive }) {
            fleetLink?.unregisterSimulatedVehicle(systemID: inst.mavlinkSystemID)
        }
        instances.removeAll { $0.id == id && !$0.isAlive }
        reconcileFleetLinkVehicleCacheAfterSitlChange()
    }

    /// Running built-in SITL session id for a Guardian sim stream key (`sysid:n`), when the process is alive.
    func sitlSessionID(forGuardianVehicleID vehicleID: String) -> UUID? {
        let prefix = "sysid:"
        guard vehicleID.hasPrefix(prefix) else { return nil }
        let rest = String(vehicleID.dropFirst(prefix.count))
        guard let systemID = Int(rest), systemID >= 1 else { return nil }
        return instances.first(where: { $0.isAlive && $0.mavlinkSystemID == systemID })?.id
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
        let systemID = inst.mavlinkSystemID
        let mavlinkURL = "udpin://0.0.0.0:\(inst.mavlinkIngressPort)"
        let stack: FleetAutopilotStack
        switch inst.platform {
        case .ardupilot:
            stack = .ardupilot
        case .px4:
            stack = .px4
        }
        link.appendSimulationLog(
            "Reconnecting MAVSDK link [vehicle=\(inst.preset.displayName) instance=\(stackIndex) mavlink_port=\(inst.mavlinkIngressPort) mavlink_sysid=\(systemID) session=\(inst.id.uuidString)] \(mavlinkURL)"
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

        guard let endpoints = allocateMavlinkEndpoints(platform: .ardupilot, stackInstance: instance) else {
            lastError = "No available MAVLink port or system id for ArduPilot SITL."
            return
        }

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.arduPilotSpec(
                root: root,
                preset: preset,
                instance: instance,
                spawnDefaults: defaults,
                mavlinkIngressPort: endpoints.ingressPort,
                mavlinkSystemID: endpoints.systemID
            )
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

        let mavlinkSystemID = endpoints.systemID
        let mavsdkIngressPort = endpoints.ingressPort

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
            link.updateSimulationLifecycleFromSitlLog(systemID: mavlinkSystemID, line: line)
        }
        runner.onTerminated = { [weak self, weak link] code in
            guard let self else { return }
            self.runners.removeValue(forKey: id)
            if let idx = self.instances.firstIndex(where: { $0.id == id }) {
                self.recordReleasedUdpPorts(from: self.instances[idx])
                var row = self.instances[idx]
                row.isAlive = false
                row.lastExitCode = code
                self.instances[idx] = row
            }
            link?.unregisterSimulatedVehicle(systemID: mavlinkSystemID)
            link?.appendSimulationLog(
                "SITL exited [platform=ArduPilot instance=\(instance) mavlink_port=\(mavsdkIngressPort) mavlink_sysid=\(mavlinkSystemID) session=\(id.uuidString)] code=\(code)"
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
                    mavlinkIngressPort: mavsdkIngressPort,
                    mavlinkSystemID: mavlinkSystemID,
                    px4GcsUdpPort: nil,
                    isAlive: true,
                    lastExitCode: nil
                )
            )
            link.registerSimulatedVehicle(
                systemID: mavlinkSystemID,
                mavlinkConnectionURL: "udpin://0.0.0.0:\(mavsdkIngressPort)",
                autopilotStack: .ardupilot,
                vehicleType: preset.fleetVehicleType,
                spawnDefaults: defaults
            )
            link.appendSimulationLog(
                "Started ArduPilot SITL [vehicle=\(preset.displayName) instance=\(instance) mavlink_port=\(mavsdkIngressPort) mavlink_sysid=\(mavlinkSystemID) session=\(id.uuidString)] primary_link=\(mavsdkIngressPort)"
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

        guard let endpoints = allocateMavlinkEndpoints(platform: .px4, stackInstance: instance) else {
            lastError = "No available MAVLink port or system id for PX4 SITL."
            return
        }

        let gcsUdpPort = endpoints.px4GcsUdpPort ?? SitlLaunchRecipe.px4SihGcsUdpPort(instance: instance)
        let mavsdkIngressPort = endpoints.ingressPort
        let mavlinkSystemID = endpoints.systemID

        let id = UUID()
        let spec: SitlProcessSpec
        do {
            spec = try SitlLaunchRecipe.px4Spec(
                root: root,
                preset: preset,
                instance: instance,
                spawnDefaults: defaults,
                mavlinkIngressPort: mavsdkIngressPort,
                mavlinkSystemID: mavlinkSystemID,
                px4GcsUdpPort: gcsUdpPort
            )
        } catch {
            lastError = error.localizedDescription
            return
        }

        let runner = SitlProcessRunner()
        runner.onLogLine = { [weak link] line in
            guard let link else { return }
            link.appendSimulationLog(line)
            link.updateSimulationLifecycleFromSitlLog(systemID: mavlinkSystemID, line: line)
        }
        runner.onTerminated = { [weak self, weak link] code in
            guard let self else { return }
            self.runners.removeValue(forKey: id)
            if let idx = self.instances.firstIndex(where: { $0.id == id }) {
                self.recordReleasedUdpPorts(from: self.instances[idx])
                var row = self.instances[idx]
                row.isAlive = false
                row.lastExitCode = code
                self.instances[idx] = row
            }
            link?.unregisterSimulatedVehicle(systemID: mavlinkSystemID)
            link?.appendSimulationLog(
                "SITL exited [platform=PX4 instance=\(instance) mavlink_port=\(mavsdkIngressPort) mavlink_sysid=\(mavlinkSystemID) session=\(id.uuidString)] code=\(code)"
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
                    mavlinkIngressPort: mavsdkIngressPort,
                    mavlinkSystemID: mavlinkSystemID,
                    px4GcsUdpPort: gcsUdpPort,
                    isAlive: true,
                    lastExitCode: nil
                )
            )
            link.registerSimulatedVehicle(
                systemID: mavlinkSystemID,
                mavlinkConnectionURL: "udpin://0.0.0.0:\(mavsdkIngressPort)",
                autopilotStack: .px4,
                vehicleType: preset.fleetVehicleType,
                spawnDefaults: defaults
            )
            link.appendSimulationLog(
                "Started PX4 SITL [sim=SIH vehicle=\(preset.displayName) model=\(preset.px4SitlSimModel()) instance=\(instance) mavlink_port=\(mavsdkIngressPort) mavlink_sysid=\(mavlinkSystemID) session=\(id.uuidString)] gcs_udp=\(gcsUdpPort) mavsdk_udpin=\(mavsdkIngressPort)"
            )
        } catch {
            lastError = error.localizedDescription
            runner.onLogLine = nil
            runner.onTerminated = nil
        }
    }

    /// Finds the next PX4 `-i` instance index (legacy mode also requires the formula GCS port to be bindable).
    private func reserveNextAvailablePx4Instance(maxScan: Int = 64) -> Int? {
        if !SitlLaunchRecipe.usesLegacySitlPorts() {
            return reserveNextSimulationInstance(maxScan: maxScan)
        }
        var candidate = instances.isEmpty ? 0 : max(0, nextSimulationInstance)
        let occupiedByGuardian = Set(instances.map(\.stackInstanceIndex))
        for _ in 0..<maxScan {
            let gcsPort = SitlLaunchRecipe.px4SihGcsUdpPort(instance: candidate)
            if !occupiedByGuardian.contains(candidate), GuardianUdpPortUtilities.isUdpPortBindable(gcsPort) {
                nextSimulationInstance = candidate + 1
                return candidate
            }
            candidate += 1
        }
        return nil
    }

    /// Inserts a running SITL row so ``resolvedFleetStreamVehicleID`` resolves without spawning (tests only).
    func seedMissionRunTestSitlRunningInstance(
        id: UUID,
        stackInstanceIndex: Int = 0,
        mavlinkIngressPort: Int? = nil,
        mavlinkSystemID: Int? = nil,
        platform: SimulationPlatform = .px4,
        preset: SimulationVehiclePreset = .uavMultirotor
    ) {
        let port: Int
        switch platform {
        case .ardupilot:
            port = mavlinkIngressPort ?? SitlLaunchRecipe.ardupilotMavproxyOutPort(instance: stackInstanceIndex)
        case .px4:
            port = mavlinkIngressPort ?? SitlLaunchRecipe.px4OffboardRemotePort(instance: stackInstanceIndex)
        }
        let sysid = mavlinkSystemID ?? (stackInstanceIndex + 1)
        let gcs: Int? = platform == .px4
            ? SitlLaunchRecipe.px4SihGcsUdpPort(instance: stackInstanceIndex)
            : nil
        instances.append(
            SitlRunningInstance(
                id: id,
                platform: platform,
                preset: preset,
                stackInstanceIndex: stackInstanceIndex,
                mavlinkIngressPort: port,
                mavlinkSystemID: sysid,
                px4GcsUdpPort: gcs,
                isAlive: true,
                lastExitCode: nil
            )
        )
    }
}
