import Foundation

/// Launches the shared Nav2 training stack (`nav2_training.launch.py`) and polls for planner readiness.
/// Runs outside the ROS bridge Python process so warm-start works even when the colcon install is stale.
@MainActor
final class FleetNav2StackRunner {
    private var launchProcess: Process?
    private var workTask: Task<Void, Never>?
    private var desiredActive = false

    var onStatus: ((String, String?) -> Void)?
    var onLogLine: ((String) -> Void)?

    var isLaunchProcessRunning: Bool { launchProcess?.isRunning == true }

    func ensureRunning() {
        guard Self.isEnabled else {
            onStatus?("unavailable", "nav2_skipped")
            return
        }
        desiredActive = true
        guard workTask == nil else { return }
        workTask = Task { [weak self] in
            await self?.runUntilReadyOrExhausted()
        }
    }

    func stop() {
        desiredActive = false
        workTask?.cancel()
        workTask = nil
        terminateLaunchProcess()
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["GUARDIAN_ROS2_SKIP_NAV2"] != "1"
    }

    private static var readyTimeoutSeconds: TimeInterval {
        let raw = ProcessInfo.processInfo.environment["GUARDIAN_NAV2_READY_TIMEOUT_S"] ?? ""
        if let value = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 30 {
            return value
        }
        return 120
    }

    private static var maxAttempts: Int {
        let raw = ProcessInfo.processInfo.environment["GUARDIAN_NAV2_MAX_START_ATTEMPTS"] ?? ""
        if let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 1 {
            return value
        }
        return 3
    }

    private static var retryDelaySeconds: TimeInterval {
        let raw = ProcessInfo.processInfo.environment["GUARDIAN_NAV2_RETRY_DELAY_S"] ?? ""
        if let value = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 1 {
            return value
        }
        return 6
    }

    private func runUntilReadyOrExhausted() async {
        defer { workTask = nil }

        guard let launchPlan = Ros2BridgeLocator.resolveLaunchPlan() else {
            onStatus?("unavailable", "ros2_runtime_missing")
            onLogLine?("Fleet Nav2: ROS 2 runtime missing (run make ros2-runtime).")
            return
        }

        var attempt = 0
        while desiredActive, !Task.isCancelled {
            attempt += 1
            if attempt > 1 {
                onStatus?("restarting", "attempt_\(attempt)")
            } else {
                onStatus?("starting", nil)
            }

            if await probePlannerServiceReady(launchPlan: launchPlan) {
                onStatus?("ready", nil)
                onLogLine?("Fleet Nav2: planner service ready.")
                return
            }

            terminateLaunchProcess()
            guard desiredActive, !Task.isCancelled else { return }

            do {
                try startLaunchProcess(launchPlan: launchPlan)
            } catch {
                onStatus?("error", error.localizedDescription)
                onLogLine?("Fleet Nav2 launch failed: \(error.localizedDescription)")
                if attempt >= Self.maxAttempts { return }
                try? await Task.sleep(nanoseconds: UInt64(Self.retryDelaySeconds * 1_000_000_000))
                continue
            }

            let ready = await waitForPlannerService(launchPlan: launchPlan, timeoutSeconds: Self.readyTimeoutSeconds)
            if ready {
                onStatus?("ready", nil)
                onLogLine?("Fleet Nav2: planner service ready.")
                return
            }

            let errTail = await captureLaunchStderrTailAfterTerminate(maxBytes: 4096)
            onStatus?("timeout", "compute_path_to_pose_unavailable")
            if errTail.isEmpty {
                onLogLine?("Fleet Nav2: planner service not ready within \(Int(Self.readyTimeoutSeconds))s.")
            } else {
                onLogLine?("Fleet Nav2 timeout. stderr: \(errTail.prefix(500))")
            }

            guard desiredActive, !Task.isCancelled, attempt < Self.maxAttempts else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.retryDelaySeconds * 1_000_000_000))
        }
    }

    private func startLaunchProcess(launchPlan: Ros2BridgeLocator.LaunchPlan) throws {
        terminateLaunchProcess()
        let setup = launchPlan.setupScriptPath
        let script = """
        set -euo pipefail
        source "\(setup)"
        exec ros2 launch guardian_ros2_vehicle_bridge nav2_training.launch.py
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", script]
        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err
        try proc.run()
        launchProcess = proc
        launchStderrPipe = err
        GuardianRos2SpawnRegistry.register(
            pid: proc.processIdentifier,
            executablePath: "/bin/bash",
            arguments: proc.arguments ?? []
        )
        onLogLine?("Fleet Nav2: ros2 launch nav2_training.launch.py (pid \(proc.processIdentifier)).")
    }

    private var launchStderrPipe: Pipe?

    private func terminateLaunchProcess() {
        guard let proc = launchProcess else {
            launchStderrPipe = nil
            return
        }
        let pid = proc.processIdentifier
        if proc.isRunning {
            proc.terminate()
        }
        GuardianRos2SpawnRegistry.unregister(pid: pid)
        launchProcess = nil
        launchStderrPipe = nil
    }

    /// Terminates the launch child, then reads stderr on a utility thread (never blocks the main actor on pipe I/O).
    private func captureLaunchStderrTailAfterTerminate(maxBytes: Int) async -> String {
        guard let proc = launchProcess, let handle = launchStderrPipe?.fileHandleForReading else {
            return ""
        }
        let pid = proc.processIdentifier
        if proc.isRunning {
            proc.terminate()
        }
        GuardianRos2SpawnRegistry.unregister(pid: pid)
        launchProcess = nil
        launchStderrPipe = nil

        return await Task.detached(priority: .utility) {
            Self.stderrTail(afterTerminating: proc, handle: handle, maxBytes: maxBytes)
        }.value
    }

    /// Bounded stderr read after the child has been signalled to stop. Safe to call off the main actor.
    nonisolated static func stderrTail(
        afterTerminating process: Process,
        handle: FileHandle,
        maxBytes: Int,
        waitForExitSeconds: TimeInterval = 5
    ) -> String {
        if process.isRunning {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                group.leave()
            }
            _ = group.wait(timeout: .now() + waitForExitSeconds)
            if process.isRunning {
                process.terminate()
            }
        }
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return "" }
        let text = String(data: data.prefix(maxBytes), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForPlannerService(launchPlan: Ros2BridgeLocator.LaunchPlan, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline, !Task.isCancelled, desiredActive {
            if await probePlannerServiceReady(launchPlan: launchPlan) {
                return true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    private func probePlannerServiceReady(launchPlan: Ros2BridgeLocator.LaunchPlan) async -> Bool {
        await Task.detached(priority: .utility) {
            Self.plannerServiceIsAvailable(setupScriptPath: launchPlan.setupScriptPath)
        }.value
    }

    private nonisolated static func plannerServiceIsAvailable(setupScriptPath: String) -> Bool {
        let script = """
        set -euo pipefail
        source "\(setupScriptPath)"
        ros2 service list
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", script]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return false
        }
        let group = DispatchGroup()
        group.enter()
        var finished = false
        DispatchQueue.global().async {
            proc.waitUntilExit()
            finished = true
            group.leave()
        }
        let waitResult = group.wait(timeout: .now() + 10)
        guard waitResult == .success, finished, proc.terminationStatus == 0 else {
            if proc.isRunning { proc.terminate() }
            return false
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let lines = Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return lines.contains("/planner_server/compute_path_to_pose")
            || lines.contains("/compute_path_to_pose")
    }
}
