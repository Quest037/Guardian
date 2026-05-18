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

    var isRunning: Bool { process?.isRunning == true }

    func start(launchPlan: Ros2BridgeLocator.LaunchPlan, configFilePath: String) throws {
        guard process == nil else { return }
        didTeardown = false

        let python = Self.resolvePython3Executable()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw FleetLinkError.startFailed("python3 not executable at \(python).")
        }

        let setup = launchPlan.setupScriptPath
        var script = """
        set -euo pipefail
        source "\(setup)"
        export GUARDIAN_ROS2_BRIDGE_CONFIG="\(configFilePath)"
        """

        if launchPlan.usesBundledMergedInstall {
            script += """

            exec ros2 run guardian_ros2_vehicle_bridge guardian_ros2_vehicle_bridge --config "\(configFilePath)"
            """
        } else {
            guard let packageRoot = launchPlan.packageSourceDirectory else {
                throw FleetLinkError.startFailed("ROS 2 bridge package root missing.")
            }
            let moduleRoot = packageRoot.path
            script += """

            export PYTHONPATH="\(moduleRoot):${PYTHONPATH:-}"
            exec "\(python)" -m guardian_ros2_vehicle_bridge.multi_vehicle_bridge --config "\(configFilePath)"
            """
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

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.consumeStdoutChunk(chunk)
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
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
            [
                "vehicle_id": entry.vehicleID,
                "stack": entry.stack,
                "vehicle_class": entry.vehicleClass,
                "ros_namespace": entry.rosNamespace,
                "autonomy_planner": entry.autonomyPlanner,
                "enabled": entry.enabled,
            ]
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

    private static func resolvePython3Executable() -> String {
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        for candidate in ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/python3"
    }
}
