import Foundation

enum SitlError: LocalizedError, Equatable {
    case missingArduPilotRuntime
    case missingSimVehicleScript
    case missingPython3
    case missingPx4AutopilotRoot
    case missingPx4SitlBuild
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArduPilotRuntime:
            return "ArduPilot SITL files are not inside this app bundle. From the Guardian repo run ./scripts/fetch_ardupilot_sitl.sh (or make sitl-runtime), then rebuild so Resources/ArduPilotSitl contains sim_vehicle.py."
        case .missingSimVehicleScript:
            return "Tools/autotest/sim_vehicle.py not found under the configured ArduPilot root."
        case .missingPython3:
            return "python3 is not available at a known path. Install Python 3 or set GUARDIAN_PYTHON."
        case .missingPx4AutopilotRoot:
            return "PX4 SITL runtime not found. Either run ./scripts/sync_px4_sitl_bundle.sh (or make px4-sitl-runtime) after building PX4, then rebuild Guardian — or set GUARDIAN_PX4_ROOT / PX4_AUTOPILOT_DIR to a PX4-Autopilot checkout with `make px4_sitl_default` already done."
        case .missingPx4SitlBuild:
            return "PX4 SITL layout is incomplete (need bin/px4 and etc/). Re-run sync_px4_sitl_bundle.sh from a successful `make px4_sitl_default` tree, or fix the checkout path."
        case .startFailed(let detail):
            return detail
        }
    }
}

/// Resolved child process for one SITL instance.
struct SitlProcessSpec: Sendable {
    let executable: String
    let arguments: [String]
    let currentDirectoryURL: URL
    /// Extra env merged onto the process environment (PATH preserved).
    let environment: [String: String]
}

/// Bundled `bin/px4` + `etc/` under `Resources/Px4SitlBundle` (see `scripts/sync_px4_sitl_bundle.sh`).
/// Optional developer override: full `PX4-Autopilot` checkout via `GUARDIAN_PX4_ROOT` or `PX4_AUTOPILOT_DIR`.
enum Px4SitlLocator {
    /// Flat bundle: `Px4SitlBundle/bin/px4` and `Px4SitlBundle/etc/` at resource root.
    static func bundleBuildPath() -> String? {
        guard let res = Bundle.module.resourceURL else { return nil }
        let build = res.appendingPathComponent("Px4SitlBundle", isDirectory: true).path
        let px4Binary = (build as NSString).appendingPathComponent("bin/px4")
        let etc = (build as NSString).appendingPathComponent("etc")
        var isDir: ObjCBool = false
        guard FileManager.default.isExecutableFile(atPath: px4Binary),
              FileManager.default.fileExists(atPath: etc, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return build
    }

    static func developerCheckoutPath() -> String? {
        for key in ["GUARDIAN_PX4_ROOT", "PX4_AUTOPILOT_DIR"] {
            guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            let expanded = (raw as NSString).expandingTildeInPath
            let cmake = (expanded as NSString).appendingPathComponent("CMakeLists.txt")
            if FileManager.default.isReadableFile(atPath: cmake) { return expanded }
        }
        return nil
    }
}

enum ArduPilotSitlLocator {
    static func bundleRootPath() -> String? {
        guard let res = Bundle.module.resourceURL else { return nil }
        let root = res.appendingPathComponent("ArduPilotSitl", isDirectory: true)
        let script = root.appendingPathComponent("Tools/autotest/sim_vehicle.py", isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: script.path) else { return nil }
        return root.path
    }

    /// Optional developer override (checked after the bundled tree).
    static func developerCheckoutPath() -> String? {
        for key in ["GUARDIAN_ARDUPILOT_ROOT", "ARDUPILOT_ROOT"] {
            guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            let expanded = (raw as NSString).expandingTildeInPath
            let script = (expanded as NSString).appendingPathComponent("Tools/autotest/sim_vehicle.py")
            if FileManager.default.isReadableFile(atPath: script) { return expanded }
        }
        return nil
    }
}

enum SitlLaunchRecipe {
    /// Per-app-run writable ArduPilot runtime root. Keeps SITL logs/state out of bundled resources.
    private static let ardupilotRuntimeSessionRoot: String = {
        let fm = FileManager.default
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("guardian-ardupilot-runtime", isDirectory: true)
            .appendingPathComponent("pid-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        return tempBase.path
    }()

    /// Per-app-run writable PX4 runtime root. Keeps PX4 state out of bundled resources so each app launch starts clean.
    private static let px4RuntimeSessionRoot: String = {
        let fm = FileManager.default
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("guardian-px4-runtime", isDirectory: true)
            .appendingPathComponent("pid-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        return tempBase.path
    }()

    /// Bundled Resources/ArduPilotSitl first, then optional developer override.
    /// This keeps release/Xcode runs using the prewarmed bundled runtime by default.
    static func ardupilotRootPath() -> String? {
        if let bundled = ArduPilotSitlLocator.bundleRootPath() { return bundled }
        if let dev = ArduPilotSitlLocator.developerCheckoutPath() { return dev }
        return nil
    }

    static func python3Executable() -> String? {
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        for candidate in ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// ArduPilot `pysim/util.py` imports `pexpect` before sim_vehicle gets far; verify the active interpreter has it.
    static func pythonHasPexpectForSitl() -> Bool {
        guard let py = python3Executable() else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: py)
        proc.arguments = ["-c", "import pexpect"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// ArduPilot waf embedding uses `empy` (import `em`); without it the SITL build fails immediately.
    static func pythonHasEmpyForSitl() -> Bool {
        guard let py = python3Executable() else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: py)
        proc.arguments = ["-c", "import em"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// ArduPilot `sim_vehicle.py` invocation for one SITL instance (`-I` separates MAVLink stacks).
    /// First spawn may run **waf** to compile `bin/arducopter` (etc.) under `ArduPilotSitl/build/sitl`; that is **one-time per tree** until the build dir is removed (e.g. clean DerivedData).
    /// MAVLink reaches Guardian via MAVProxy’s default `--out` to UDP 14550+10*instance (see `sim_vehicle.py`).
    ///
    /// Do **not** pass `--console`: MAVProxy’s console module expects a TTY and exits immediately when spawned from `Process`, which ends `sim_vehicle.py` and drops the UI row.
    static func arduPilotSpec(root: String, preset: SimulationVehiclePreset, instance: Int) throws -> SitlProcessSpec {
        guard let python = python3Executable() else { throw SitlError.missingPython3 }
        let script = (root as NSString).appendingPathComponent("Tools/autotest/sim_vehicle.py")
        guard FileManager.default.isReadableFile(atPath: script) else { throw SitlError.missingSimVehicleScript }

        let (vehicle, frame) = preset.ardupilotSimVehicleKind()
        var args: [String] = [script, "-v", vehicle, "-I", "\(instance)"]
        if shouldUseNoRebuildForArduPilot(root: root, vehicle: vehicle) {
            args.append("--no-rebuild")
        }
        let runDir = (ardupilotRuntimeSessionRoot as NSString).appendingPathComponent("instance-\(instance)")
        try FileManager.default.createDirectory(
            atPath: runDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        args.append(contentsOf: ["--use-dir", runDir])
        if let frame {
            args.append(contentsOf: ["-f", frame])
        }

        let cwd = URL(fileURLWithPath: root, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PATH"] = Self.augmentedPATH(existing: env["PATH"] ?? "")
        return SitlProcessSpec(executable: python, arguments: args, currentDirectoryURL: cwd, environment: env)
    }

    /// Use prewarmed binaries when available; otherwise let sim_vehicle perform its normal build fallback.
    private static func shouldUseNoRebuildForArduPilot(root: String, vehicle: String) -> Bool {
        let binaryName: String
        switch vehicle {
        case "ArduCopter":
            binaryName = "arducopter"
        case "ArduPlane":
            binaryName = "arduplane"
        case "Rover", "ArduBoat":
            binaryName = "ardurover"
        case "ArduSub":
            binaryName = "ardusub"
        default:
            return false
        }
        let binaryPath = (root as NSString).appendingPathComponent("build/sitl/bin/\(binaryName)")
        return FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    /// Default MAVProxy UDP output base for ArduPilot SITL (`14550 + 10 * instance`).
    static func ardupilotMavproxyOutPort(instance: Int) -> Int {
        14_550 + (10 * instance)
    }

    /// Prepends common locations for `mavproxy.py` (pip / Homebrew) so `sim_vehicle` can find MAVProxy.
    static func augmentedPATH(existing: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var prefixes = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        let pyRoot = URL(fileURLWithPath: home).appendingPathComponent("Library/Python", isDirectory: true)
        if let vers = try? FileManager.default.contentsOfDirectory(at: pyRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for u in vers {
                let bin = u.appendingPathComponent("bin", isDirectory: true)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: bin.path, isDirectory: &isDir), isDir.boolValue {
                    prefixes.append(bin.path)
                }
            }
        }
        let prefix = prefixes.joined(separator: ":")
        if existing.isEmpty { return prefix }
        return prefix + ":" + existing
    }

    /// Whether MAVProxy is discoverable on the augmented PATH (required unless using `--no-mavproxy`).
    static func mavproxyLikelyAvailable(environment: [String: String]) -> Bool {
        let path = environment["PATH"] ?? ""
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("mavproxy.py").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return true }
        }
        return false
    }

    /// MAVProxy’s `rline` module requires `gnureadline` on typical macOS Python installs.
    static func pythonHasGnureadlineForMavproxy() -> Bool {
        guard let py = python3Executable() else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: py)
        proc.arguments = ["-c", "import gnureadline"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Tries common CMake output folder names for POSIX SITL (`make px4_sitl_default`, etc.).
    private static let px4SitlBuildDirNames = ["px4_sitl_default", "px4_macos_default", "px4_macos_sitl_default"]

    /// Developer checkout wins (same pattern as ArduPilot); otherwise bundled `Px4SitlBundle`.
    static func px4SitlRootPath() -> String? {
        if let dev = Px4SitlLocator.developerCheckoutPath() { return dev }
        if let bundled = Px4SitlLocator.bundleBuildPath() { return bundled }
        return nil
    }

    /// UDP port PX4’s `px4-rc.mavlink` binds for the “GCS” MAVLink instance in SIH SITL (`18570 + px4_instance`).
    static func px4SihGcsUdpPort(instance: Int) -> Int {
        18_570 + instance
    }

    /// PX4 `px4-rc.mavlink` offboard/API remote UDP port (`14540 + px4_instance`).
    /// This is unique per instance and suitable for per-vehicle MAVSDK ingestion.
    static func px4OffboardRemotePort(instance: Int) -> Int {
        14_540 + min(instance, 9)
    }

    /// Resolves `build/<target>/{bin/px4, etc, rootfs}` under a PX4-Autopilot checkout, **or** a flat bundle root (`bin`, `etc` directly under `root`).
    static func px4ResolvedBuildLayout(root: String) -> (build: String, px4Binary: String, etc: String, rootfsBase: String)? {
        let fm = FileManager.default
        let directPx4 = (root as NSString).appendingPathComponent("bin/px4")
        let directEtc = (root as NSString).appendingPathComponent("etc")
        var isDir: ObjCBool = false
        if fm.isExecutableFile(atPath: directPx4),
           fm.fileExists(atPath: directEtc, isDirectory: &isDir), isDir.boolValue {
            let rootfsBase = (root as NSString).appendingPathComponent("rootfs")
            return (root, directPx4, directEtc, rootfsBase)
        }
        for dirName in px4SitlBuildDirNames {
            let build = (root as NSString).appendingPathComponent("build/\(dirName)")
            let px4Binary = (build as NSString).appendingPathComponent("bin/px4")
            let etc = (build as NSString).appendingPathComponent("etc")
            let rootfsBase = (build as NSString).appendingPathComponent("rootfs")
            var buildEtcIsDir: ObjCBool = false
            guard fm.fileExists(atPath: etc, isDirectory: &buildEtcIsDir), buildEtcIsDir.boolValue else { continue }
            guard fm.isExecutableFile(atPath: px4Binary) else { continue }
            return (build, px4Binary, etc, rootfsBase)
        }
        return nil
    }

    /// Spawns `bin/px4` with `PX4_SIM_MODEL` set for built-in SIH airframes (no Gazebo / jMAVSim).
    static func px4Spec(root: String, preset: SimulationVehiclePreset, instance: Int) throws -> SitlProcessSpec {
        guard let layout = px4ResolvedBuildLayout(root: root) else {
            throw SitlError.missingPx4SitlBuild
        }

        // Runtime state must be outside bundled resources (logs/dataman/params/locks), otherwise stale
        // instance state in DerivedData can poison "first PX4 sim" on subsequent app runs.
        let runtimeRootfsBase = (px4RuntimeSessionRoot as NSString).appendingPathComponent("rootfs")
        let instanceRootfs = (runtimeRootfsBase as NSString).appendingPathComponent("\(instance)")
        try FileManager.default.createDirectory(
            atPath: instanceRootfs,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let model = preset.px4SitlSimModel()
        var env = ProcessInfo.processInfo.environment
        env["PX4_SIM_MODEL"] = model
        env["HEADLESS"] = "1"
        // rcS runs `. px4-alias.sh`; that file lives next to px4 under bin/ (must be on PATH).
        let binDir = (layout.build as NSString).appendingPathComponent("bin")
        env["PATH"] = binDir + ":" + augmentedPATH(existing: env["PATH"] ?? "")

        let cwd = URL(fileURLWithPath: instanceRootfs, isDirectory: true)
        let args = ["-i", "\(instance)", "-d", layout.etc]
        return SitlProcessSpec(
            executable: layout.px4Binary,
            arguments: args,
            currentDirectoryURL: cwd,
            environment: env
        )
    }
}

extension SimulationVehiclePreset {
    /// Maps Guardian presets to `sim_vehicle.py -v` / `-f` pairs.
    func ardupilotSimVehicleKind() -> (vehicle: String, frame: String?) {
        switch self {
        case .uavMultirotor:
            return ("ArduCopter", "quad")
        case .uavFixedWing:
            return ("ArduPlane", nil)
        case .uavVTOL:
            return ("ArduPlane", "quadplane")
        case .ugvWheeled:
            return ("Rover", "rover")
        case .ugvTracked:
            return ("Rover", "skid")
        case .ugvLegged:
            return ("Rover", "balancebot")
        case .usv:
            return ("ArduBoat", "motorboat")
        case .uuv:
            return ("ArduSub", "vectored")
        }
    }

    /// `PX4_SIM_MODEL` value matching `ROMFS/.../airframes/<id>_<model>` (SIH = no external simulator).
    func px4SitlSimModel() -> String {
        switch self {
        case .uavMultirotor:
            return "sihsim_quadx"
        case .uavFixedWing:
            return "sihsim_airplane"
        case .uavVTOL:
            return "sihsim_standard_vtol"
        case .ugvWheeled, .ugvTracked, .ugvLegged:
            return "sihsim_rover_ackermann"
        case .usv, .uuv:
            // No SIH marine airframe in default ROMFS; use quad SIH so telemetry still exercises the stack.
            return "sihsim_quadx"
        }
    }
}
