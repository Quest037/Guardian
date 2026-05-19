import Foundation

/// Runs `guardian_ros2_vehicle_bridge` under a sourced ROS 2 environment; JSON lines on stdout.
@MainActor
final class Ros2BridgeRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var lineBuffer = ""
    private var didTeardown = false

    var onStdoutLine: ((String) -> Void)?
    var onStderrLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?
    /// When false, readability handlers skip scheduling `consumeStdoutChunk` on the main actor.
    var shouldDeliverChunksOnMainActor: () -> Bool = { true }

    var isRunning: Bool { process?.isRunning == true }

    func start(launchPlan: Ros2BridgeLocator.LaunchPlan, configFilePath: String) throws {
        guard process == nil else { return }
        didTeardown = false

        let setup = launchPlan.setupScriptPath
        var script = """
        set -euo pipefail
        source "\(setup)"
        export GUARDIAN_ROS2_BRIDGE_CONFIG="\(configFilePath)"
        """

        // Prefer in-app Python sources over a stale colcon install (ensures ensure_nav2, boot Nav2, retries).
        // Use ``python3`` from the sourced ROS environment (RoboStack 3.11) — not Xcode/system 3.9 before ``source``.
        if let packageRoot = Ros2BridgeLocator.bundledPackageSourceURL() {
            script += Ros2BridgeLocator.bashLaunchGuardianBridgeModule(
                configFilePath: configFilePath,
                packageSourceRoot: packageRoot.path
            )
        } else if launchPlan.usesBundledMergedInstall {
            script += """

            export GUARDIAN_NAV2_LAUNCH_DISABLED=1
            exec ros2 run guardian_ros2_vehicle_bridge guardian_ros2_vehicle_bridge --config "\(configFilePath)"
            """
        } else {
            guard let packageRoot = launchPlan.packageSourceDirectory else {
                throw FleetLinkError.startFailed("ROS 2 bridge package root missing.")
            }
            script += Ros2BridgeLocator.bashLaunchGuardianBridgeModule(
                configFilePath: configFilePath,
                packageSourceRoot: packageRoot.path
            )
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", script]
        proc.currentDirectoryURL = launchPlan.packageSourceDirectory
            ?? URL(fileURLWithPath: (setup as NSString).deletingLastPathComponent)

        let input = Pipe()
        let out = Pipe()
        let err = Pipe()
        proc.standardInput = input
        proc.standardOutput = out
        proc.standardError = err
        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.teardownOnce(exitCode: finished.terminationStatus)
            }
        }

        try proc.run()
        process = proc
        stdinPipe = input
        stdoutPipe = out
        stderrPipe = err
        GuardianRos2SpawnRegistry.register(
            pid: proc.processIdentifier,
            executablePath: "/bin/bash",
            arguments: proc.arguments ?? []
        )

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard self.shouldDeliverChunksOnMainActor() else { return }
                self.consumeStdoutChunk(chunk)
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard self.shouldDeliverChunksOnMainActor() else { return }
                self.consumeStderrChunk(chunk)
            }
        }
    }

    func stop() {
        guard let proc = process, !didTeardown else { return }
        if proc.isRunning {
            sendStdinCommand(["type": "shutdown"])
            proc.terminate()
        } else {
            teardownOnce(exitCode: proc.terminationStatus)
        }
    }

    func sendEnsureNav2Stack() {
        sendStdinCommand(["type": "ensure_nav2"])
    }

    func sendPlanPath(
        requestID: UUID,
        vehicleID: String,
        rosNamespace: String,
        start: TrainingTaskPose,
        goal: TrainingTaskPose
    ) {
        sendStdinCommand([
            "type": "plan_path",
            "request_id": requestID.uuidString,
            "vehicle_id": vehicleID,
            "ros_namespace": rosNamespace,
            "start": [
                "lat": start.latitudeDeg,
                "lon": start.longitudeDeg,
                "heading_deg": start.headingDeg,
            ],
            "goal": [
                "lat": goal.latitudeDeg,
                "lon": goal.longitudeDeg,
                "heading_deg": goal.headingDeg,
            ],
        ])
    }

    func updateVehicles(_ vehicles: [Ros2VehicleBridgeEntry]) {
        let payload: [[String: Any]] = vehicles.map { entry in
            var row: [String: Any] = [
                "vehicle_id": entry.vehicleID,
                "stack": entry.stack,
                "vehicle_class": entry.vehicleClass,
                "ros_namespace": entry.rosNamespace,
                "autonomy_planner": entry.autonomyPlanner,
                "enabled": entry.enabled,
            ]
            if let brainId = entry.brainId, !brainId.isEmpty {
                row["brain_id"] = brainId
            }
            if let brainVersion = entry.brainVersion {
                row["brain_version"] = brainVersion
            }
            if let nav2 = entry.nav2ParamOverlayJSON, !nav2.isEmpty {
                row["nav2_param_overlay_json"] = nav2
            }
            if let as2 = entry.aerostack2ParamOverlayJSON, !as2.isEmpty {
                row["aerostack2_param_overlay_json"] = as2
            }
            return row
        }
        sendStdinCommand([
            "type": "set_vehicles",
            "vehicles": payload,
        ])
    }

    private func sendStdinCommand(_ payload: [String: Any]) {
        guard let input = stdinPipe else { return }
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consumeStdoutChunk(_ chunk: String) {
        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = lineBuffer.index(after: nl)
            lineBuffer = String(lineBuffer[after...])
            if !line.isEmpty {
                onStdoutLine?(line)
            }
        }
    }

    private func consumeStderrChunk(_ chunk: String) {
        for part in chunk.split(whereSeparator: \.isNewline) {
            let line = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                onStderrLine?(TerminalLogFormatting.stripANSICodes(line))
            }
        }
    }

    private func teardownOnce(exitCode: Int32) {
        guard !didTeardown else { return }
        didTeardown = true
        if let pid = process?.processIdentifier {
            GuardianRos2SpawnRegistry.unregister(pid: pid)
        }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process?.terminationHandler = nil
        process = nil
        lineBuffer = ""
        let cb = onTerminated
        onTerminated = nil
        onStdoutLine = nil
        onStderrLine = nil
        cb?(exitCode)
    }

}
