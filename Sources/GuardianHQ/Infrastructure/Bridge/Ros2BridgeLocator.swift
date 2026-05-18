import Foundation

/// Resolved ROS 2 paths for the PX4 sidecar (bundled runtime first, like ``MavsdkServerLocator``).
enum Ros2BridgeLocator {
    struct LaunchPlan: Equatable, Sendable {
        /// Single `setup.bash` to source (bundled merged install or system ROS).
        var setupScriptPath: String
        /// When true, run via `ros2 run` from the merged install (no PYTHONPATH hack).
        var usesBundledMergedInstall: Bool
        /// Editable package root when running from source without a merged install.
        var packageSourceDirectory: URL?
    }

    /// Chained setup (RoboStack underlay + Guardian overlay) from `make ros2-runtime`.
    static func bundledRuntimeInstallSetupPath() -> String? {
        guard let base = Bundle.module.resourceURL else { return nil }
        let runtime = base.appendingPathComponent("Ros2Runtime", isDirectory: true)
        let candidates = [
            runtime.appendingPathComponent("install/setup.bash", isDirectory: false),
            runtime.appendingPathComponent("overlay/install/setup.bash", isDirectory: false),
        ]
        for url in candidates {
            if FileManager.default.isReadableFile(atPath: url.path) { return url.path }
        }
        return nil
    }

    static func bundledMicroXrceAgentPath() -> String? {
        guard let base = Bundle.module.resourceURL else { return nil }
        let path = base
            .appendingPathComponent("Ros2Runtime", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("MicroXRCEAgent", isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// `Resources/Ros2VehicleBridge/guardian_ros2_vehicle_bridge` for dev fallback.
    static func bundledPackageSourceURL() -> URL? {
        guard let base = Bundle.module.resourceURL else { return nil }
        let dir = base
            .appendingPathComponent("Ros2VehicleBridge", isDirectory: true)
            .appendingPathComponent("guardian_ros2_vehicle_bridge", isDirectory: true)
        let module = dir.appendingPathComponent("guardian_ros2_vehicle_bridge", isDirectory: true)
        guard FileManager.default.fileExists(atPath: module.path) else { return nil }
        return dir
    }

    /// Autonomy stack sources (`navigation2`, `aerostack2`, …) when vendored in the bundle.
    static func bundledAutonomyStacksUpstreamURL() -> URL? {
        guard let base = Bundle.module.resourceURL else { return nil }
        let dir = base
            .appendingPathComponent("Ros2AutonomyStacks", isDirectory: true)
            .appendingPathComponent("upstream", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("navigation2").path) else {
            return nil
        }
        return dir
    }

    static func resolveLaunchPlan() -> LaunchPlan? {
        if let bundled = bundledRuntimeInstallSetupPath() {
            return LaunchPlan(
                setupScriptPath: bundled,
                usesBundledMergedInstall: true,
                packageSourceDirectory: nil
            )
        }
        if let envRoot = ProcessInfo.processInfo.environment["GUARDIAN_ROS2_RUNTIME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envRoot.isEmpty {
            let setup = (envRoot as NSString).appendingPathComponent("install/setup.bash")
            if FileManager.default.isReadableFile(atPath: setup) {
                return LaunchPlan(
                    setupScriptPath: setup,
                    usesBundledMergedInstall: true,
                    packageSourceDirectory: nil
                )
            }
        }
        guard let rosSetup = resolveSystemRosSetupScriptPath() else { return nil }
        guard let packageRoot = bundledPackageSourceURL() else { return nil }
        return LaunchPlan(
            setupScriptPath: rosSetup,
            usesBundledMergedInstall: false,
            packageSourceDirectory: packageRoot
        )
    }

    static func resolveMicroXrceAgentPath() -> String? {
        if let bundled = bundledMicroXrceAgentPath() { return bundled }
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_MICROXRCE_AGENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        for name in ["MicroXRCEAgent", "micro-xrce-dds-agent"] {
            if let path = whichExecutable(named: name) { return path }
        }
        for candidate in [
            "/opt/homebrew/bin/MicroXRCEAgent",
            "/usr/local/bin/MicroXRCEAgent",
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func resolveSystemRosSetupScriptPath() -> String? {
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_ROS_SETUP"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isReadableFile(atPath: env) {
            return env
        }
        for prefix in systemRosPrefixCandidates() {
            for name in ["setup.bash", "setup.zsh", "local_setup.bash"] {
                let path = (prefix as NSString).appendingPathComponent(name)
                if FileManager.default.isReadableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// `/opt/ros/*` and `~/.guardian/ros/humble` (RoboStack install from `make ros2-system-install`).
    private static func systemRosPrefixCandidates() -> [String] {
        var prefixes: [String] = []
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_ROS2_PREFIX"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            prefixes.append(env)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        prefixes.append("\(home)/.guardian/ros/humble")
        prefixes.append(contentsOf: ["/opt/ros/jazzy", "/opt/ros/iron", "/opt/ros/humble", "/opt/ros/rolling"])
        return prefixes
    }

    private static func whichExecutable(named: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [named]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
