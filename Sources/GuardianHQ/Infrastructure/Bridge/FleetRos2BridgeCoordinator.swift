import Foundation

/// Owns Micro XRCE-DDS Agent + `guardian_ros2_vehicle_bridge` for all PX4 fleet sessions.
@MainActor
final class FleetRos2BridgeCoordinator {
    private let xrceAgent = MicroXrceAgentRunner()
    private let bridge = Ros2BridgeRunner()
    private let nav2StackRunner = FleetNav2StackRunner()
    private var configFileURL: URL?
    private var lastUnavailableReason: String?
    private var didLogUnavailable = false
    /// Keeps the ROS bridge process alive with no PX4 vehicles so fleet Nav2 can warm-start at app launch.
    private var fleetNav2WarmStartDesired = false
    private var nav2StackRestartTask: Task<Void, Never>?

    var processPhase: Ros2BridgeProcessPhase = .inactive
    var onProcessPhaseChanged: ((Ros2BridgeProcessPhase) -> Void)?
    var onVehicleConnectionState: ((String, Ros2VehicleConnectionState) -> Void)?
    var onAutonomyPlannerRegistered: ((String, GuardianAutonomyPlannerKind) -> Void)?
    /// Fired when the shared Training Nav2 stack becomes ready or stops (`true` = ready).
    var onNav2TrainingStackReadyChanged: ((Bool) -> Void)?
    /// `status` from bridge JSON (`starting`, `ready`, `timeout`, `unavailable`, …); optional `message` detail.
    var onNav2TrainingStackStatusChanged: ((String, String?) -> Void)?
    var onLogLine: ((String) -> Void)?

    private var pendingNav2PlanPaths: [UUID: CheckedContinuation<TrainingNav2PlanPathResponse, Never>] = [:]

    func stopAll() {
        nav2StackRestartTask?.cancel()
        nav2StackRestartTask = nil
        fleetNav2WarmStartDesired = false
        nav2StackRunner.stop()
        teardownBridgeProcesses()
        setProcessPhase(.inactive)
    }

    private func teardownBridgeProcesses() {
        resolveAllPendingNav2Plans(with: .unavailable)
        bridge.stop()
        xrceAgent.stop()
        configFileURL = nil
    }

    /// Starts the shared Nav2 stack at application launch (non-blocking; bridge host only, no PX4 vehicles required).
    func beginFleetNav2WarmStart() {
        guard Self.isFleetNav2WarmStartEnabled else {
            onNav2TrainingStackStatusChanged?("unavailable", "nav2_skipped")
            onNav2TrainingStackReadyChanged?(false)
            return
        }
        fleetNav2WarmStartDesired = true
        wireNav2StackRunnerCallbacksIfNeeded()
        nav2StackRunner.ensureRunning()
        reconcile(vehicles: [])
    }

    func restartFleetNav2Stack() {
        guard fleetNav2WarmStartDesired, Self.isFleetNav2WarmStartEnabled else { return }
        wireNav2StackRunnerCallbacksIfNeeded()
        nav2StackRunner.stop()
        nav2StackRunner.ensureRunning()
    }

    private func wireNav2StackRunnerCallbacksIfNeeded() {
        nav2StackRunner.onStatus = { [weak self] status, message in
            guard let self else { return }
            self.onLogLine?("Nav2 training stack: \(status)")
            self.onNav2TrainingStackStatusChanged?(status, message)
            switch status {
            case "ready":
                self.onNav2TrainingStackReadyChanged?(true)
            case "stopped", "unavailable", "error", "timeout":
                self.onNav2TrainingStackReadyChanged?(false)
            default:
                break
            }
        }
        nav2StackRunner.onLogLine = { [weak self] line in
            self?.onLogLine?(line)
        }
    }

    func reconcile(vehicles: [Ros2VehicleBridgeEntry]) {
        let nav2OnlyHost = vehicles.isEmpty && fleetNav2WarmStartDesired
        guard !vehicles.isEmpty || nav2OnlyHost else {
            if bridge.isRunning {
                bridge.updateVehicles([])
            } else {
                stopAll()
            }
            return
        }

        guard let launchPlan = Ros2BridgeLocator.resolveLaunchPlan() else {
            onNav2TrainingStackStatusChanged?("unavailable", "ros2_runtime_missing")
            onNav2TrainingStackReadyChanged?(false)
            markUnavailable(
                "ROS 2 runtime missing from app bundle. Run `make ros2-runtime` before building Guardian, or install ROS 2 Humble/Jazzy for development."
            )
            scheduleNav2StackRestartIfRecoverable()
            return
        }

        if !vehicles.isEmpty, !xrceAgent.isRunning {
            guard let agentPath = Ros2BridgeLocator.resolveMicroXrceAgentPath() else {
                markUnavailable(
                    "Micro XRCE-DDS Agent missing. Run `make ros2-runtime` or install micro-xrce-dds-agent."
                )
                return
            }
            do {
                xrceAgent.onStderrLine = { [weak self] line in
                    self?.onLogLine?("MicroXRCEAgent: \(line)")
                }
                xrceAgent.onTerminated = { [weak self] code in
                    self?.onLogLine?("MicroXRCEAgent exited (code \(code)).")
                }
                try xrceAgent.start(executablePath: agentPath, udpPort: Ros2BridgeRuntime.microXrceUdpPort)
                onLogLine?("Started Micro XRCE-DDS Agent on UDP \(Ros2BridgeRuntime.microXrceUdpPort).")
            } catch {
                markUnavailable(error.localizedDescription)
                return
            }
        }

        let configPath: String
        do {
            configPath = try writeConfig(vehicles: vehicles)
        } catch {
            markUnavailable("ROS 2 bridge config write failed: \(error.localizedDescription)")
            return
        }

        lastUnavailableReason = nil
        didLogUnavailable = false

        if bridge.isRunning {
            setProcessPhase(.running)
            bridge.updateVehicles(vehicles)
            let label = nav2OnlyHost ? "Nav2 warm-start host" : "ROS 2 bridge vehicles updated (\(vehicles.count))"
            onLogLine?(label)
            return
        }

        setProcessPhase(.starting)
        bridge.onStdoutLine = { [weak self] line in
            self?.handleStdoutLine(line)
        }
        bridge.onStderrLine = { [weak self] line in
            self?.onLogLine?("ros2_bridge: \(line)")
        }
        bridge.onTerminated = { [weak self] code in
            guard let self else { return }
            self.onLogLine?("ROS 2 bridge exited (code \(code)).")
            self.setProcessPhase(.failed)
            if self.fleetNav2WarmStartDesired {
                self.scheduleNav2StackRestartIfRecoverable()
            }
        }
        do {
            try bridge.start(launchPlan: launchPlan, configFilePath: configPath)
            setProcessPhase(.running)
            if nav2OnlyHost {
                onLogLine?("Fleet Nav2 warm-start bridge started (no PX4 vehicles yet).")
            } else {
                onLogLine?("ROS 2 vehicle bridge started for \(vehicles.count) PX4 vehicle(s).")
            }
        } catch {
            onNav2TrainingStackStatusChanged?("error", error.localizedDescription)
            onNav2TrainingStackReadyChanged?(false)
            markUnavailable(error.localizedDescription)
            scheduleNav2StackRestartIfRecoverable()
        }
    }

    private static var isFleetNav2WarmStartEnabled: Bool {
        ProcessInfo.processInfo.environment["GUARDIAN_ROS2_SKIP_NAV2"] != "1"
    }

    private func scheduleNav2StackRestartIfRecoverable() {
        guard fleetNav2WarmStartDesired, Self.isFleetNav2WarmStartEnabled else { return }
        nav2StackRestartTask?.cancel()
        nav2StackRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.fleetNav2WarmStartDesired else { return }
            self.nav2StackRunner.ensureRunning()
            if !self.bridge.isRunning {
                self.reconcile(vehicles: [])
            }
        }
    }

    private func writeConfig(vehicles: [Ros2VehicleBridgeEntry]) throws -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Guardian", isDirectory: true)
        guard let dir else {
            throw FleetLinkError.startFailed("Application Support directory unavailable.")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ros2_bridge_vehicles.yaml", isDirectory: false)
        let yaml = Self.yamlDocument(vehicles: vehicles)
        try yaml.write(to: file, atomically: true, encoding: .utf8)
        configFileURL = file
        return file.path
    }

    private static func yamlDocument(vehicles: [Ros2VehicleBridgeEntry]) -> String {
        var lines = [
            "timing:",
            "  discovery_interval_s: 2.0",
            "  stale_topic_s: 5.0",
            "vehicles:",
        ]
        for v in vehicles {
            lines.append("  - vehicle_id: \"\(escapeYAML(v.vehicleID))\"")
            lines.append("    stack: \(v.stack)")
            lines.append("    vehicle_class: \(v.vehicleClass)")
            lines.append("    ros_namespace: \"\(escapeYAML(v.rosNamespace))\"")
            lines.append("    autonomy_planner: \(v.autonomyPlanner)")
            lines.append("    enabled: \(v.enabled ? "true" : "false")")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Request an A→B path for Training map overlay (Nav2 when stack is up; geodesic fallback otherwise).
    func requestTrainingNav2PlanPath(
        vehicleID: String,
        rosNamespace: String,
        start: TrainingTaskPose,
        goal: TrainingTaskPose
    ) async -> TrainingNav2PlanPathResponse {
        guard bridge.isRunning else { return .unavailable }
        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            pendingNav2PlanPaths[requestID] = continuation
            bridge.sendPlanPath(
                requestID: requestID,
                vehicleID: vehicleID,
                rosNamespace: rosNamespace,
                start: start,
                goal: goal
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self else { return }
                guard let pending = self.pendingNav2PlanPaths.removeValue(forKey: requestID) else { return }
                pending.resume(returning: .unavailable)
            }
        }
    }

    private func resolveAllPendingNav2Plans(with response: TrainingNav2PlanPathResponse) {
        let pending = pendingNav2PlanPaths
        pendingNav2PlanPaths.removeAll()
        for continuation in pending.values {
            continuation.resume(returning: response)
        }
    }

    private func handleStdoutLine(_ line: String) {
        guard let event = Ros2BridgeStdoutParser.parse(line: line) else { return }
        switch event.type {
        case "ros2_connection_state":
            if let vehicleID = event.vehicleID, let state = event.state {
                onVehicleConnectionState?(vehicleID, state)
            }
        case "ros2_bridge_listening":
            setProcessPhase(.running)
        case "ros2_autonomy_planner":
            if let vehicleID = event.vehicleID,
               let raw = event.plannerKind,
               let kind = GuardianAutonomyPlannerKind(rawValue: raw) {
                onAutonomyPlannerRegistered?(vehicleID, kind)
            }
        case "ros2_bridge_error":
            if let message = event.message {
                onLogLine?("ROS 2 bridge error: \(message)")
            }
        case "ros2_nav2_training_stack":
            // Swift ``FleetNav2StackRunner`` owns launch; ignore duplicate bridge poll events unless runner is idle.
            guard !nav2StackRunner.isLaunchProcessRunning else { return }
            if let status = event.trainingStackStatus {
                onLogLine?("Nav2 training stack (bridge): \(status)")
                onNav2TrainingStackStatusChanged?(status, event.message)
                switch status {
                case "ready":
                    onNav2TrainingStackReadyChanged?(true)
                case "stopped", "unavailable", "error", "timeout":
                    onNav2TrainingStackReadyChanged?(false)
                default:
                    break
                }
            }
        case "ros2_nav2_plan_path":
            if let payload = event.nav2PlanPath,
               let continuation = pendingNav2PlanPaths.removeValue(forKey: payload.requestID) {
                let source = TrainingNav2PlanPathResponse.Source(rawValue: payload.source) ?? .error
                if payload.ok, payload.points.count >= 2 {
                    continuation.resume(
                        returning: TrainingNav2PlanPathResponse(
                            points: payload.points,
                            source: source == .nav2 ? .nav2 : .geodesicFallback,
                            message: payload.message
                        )
                    )
                } else {
                    continuation.resume(
                        returning: TrainingNav2PlanPathResponse(
                            points: [],
                            source: .error,
                            message: payload.message
                        )
                    )
                }
            }
        default:
            break
        }
    }

    private func markUnavailable(_ reason: String) {
        if lastUnavailableReason != reason || !didLogUnavailable {
            onLogLine?(reason)
            didLogUnavailable = true
        }
        lastUnavailableReason = reason
        teardownBridgeProcesses()
        setProcessPhase(.unavailable)
    }

    private func setProcessPhase(_ phase: Ros2BridgeProcessPhase) {
        guard processPhase != phase else { return }
        processPhase = phase
        onProcessPhaseChanged?(phase)
    }
}
