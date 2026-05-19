import Foundation

enum GazeboError: LocalizedError, Equatable {
    case missingRuntime
    case missingWorldFile(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRuntime:
            return "Gazebo is not bundled in this build. From the Guardian repo run ./scripts/fetch_gazebo_runtime.sh (or make gazebo-runtime) after installing Gazebo Harmonic, then rebuild."
        case .missingWorldFile(let path):
            return "Training world file not found: \(path)"
        case .startFailed(let detail):
            return detail
        }
    }
}

/// Resolved child process for one Gazebo world instance.
struct GazeboProcessSpec: Sendable {
    let executable: String
    let arguments: [String]
    let currentDirectoryURL: URL
    let environment: [String: String]
    let worldPath: String
    let logDirectoryURL: URL
}

/// Bundled `GazeboRuntime/bin/gz` (see `scripts/fetch_gazebo_runtime.sh`).
/// Optional developer override: `GUARDIAN_GZ_INSTALL_PREFIX` or `GUARDIAN_GZ_ROOT`.
enum GazeboLocator {
    static let bundleResourceName = "GazeboRuntime"

    static func bundleRootURL() -> URL? {
        guard let res = Bundle.module.resourceURL else { return nil }
        let root = res.appendingPathComponent(bundleResourceName, isDirectory: true)
        let gz = root.appendingPathComponent("bin/gz", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: gz.path) else { return nil }
        return root
    }

    static func developerInstallPrefixURL() -> URL? {
        for key in ["GUARDIAN_GZ_INSTALL_PREFIX", "GUARDIAN_GZ_ROOT"] {
            guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            let expanded = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            let gz = expanded.appendingPathComponent("bin/gz", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: gz.path) { return expanded }
        }
        return nil
    }

    /// Apple Silicon / Intel Homebrew when the bundled runtime was not staged or has broken symlinks.
    static func homebrewInstallPrefixURL() -> URL? {
        for base in ["/opt/homebrew", "/usr/local"] {
            let root = URL(fileURLWithPath: base, isDirectory: true)
            let gz = root.appendingPathComponent("bin/gz", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: gz.path) { return root }
        }
        return nil
    }

    static func resolvedRootURL() -> URL? {
        developerInstallPrefixURL() ?? bundleRootURL() ?? homebrewInstallPrefixURL()
    }

    static func gzExecutablePath() -> String? {
        guard let root = resolvedRootURL() else { return nil }
        let path = root.appendingPathComponent("bin/gz", isDirectory: false).path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static let websocketServerPluginName = "libgz-launch-websocket-server.dylib"

    /// `gz launch` plugin dirs (bundled runtime + Homebrew prefix when present).
    static func gzLaunchPluginDirectories() -> [URL] {
        var dirs: [URL] = []
        func appendIfDirectory(_ url: URL) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
            guard !dirs.contains(url) else { return }
            dirs.append(url)
        }

        if let root = resolvedRootURL() {
            appendIfDirectory(root.appendingPathComponent("lib/gz-launch-7/plugins", isDirectory: true))
        }
        for prefix in [developerInstallPrefixURL(), homebrewInstallPrefixURL()].compactMap({ $0 }) {
            appendIfDirectory(prefix.appendingPathComponent("lib/gz-launch-7/plugins", isDirectory: true))
        }
        for base in ["/opt/homebrew", "/usr/local"] {
            appendIfDirectory(URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent("lib/gz-launch-7/plugins", isDirectory: true))
        }
        return dirs
    }

    /// Harmonic web viewport needs this dylib; Homebrew omits it unless built with `libwebsockets`.
    static func websocketServerPluginURL() -> URL? {
        for dir in gzLaunchPluginDirectories() {
            let candidate = dir.appendingPathComponent(websocketServerPluginName, isDirectory: false)
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static var isWebsocketServerPluginAvailable: Bool {
        websocketServerPluginURL() != nil
    }

    /// `gz-launch` binary (prefer over `gz launch` so we can set `DYLD_LIBRARY_PATH` on the real executable).
    static func gzLaunchExecutablePath() -> String? {
        for root in [resolvedRootURL(), homebrewInstallPrefixURL(), developerInstallPrefixURL()].compactMap({ $0 }) {
            let launch = root.appendingPathComponent("lib/gz/launch7/gz-launch", isDirectory: false).path
            if FileManager.default.isExecutableFile(atPath: launch) { return launch }
        }
        return nil
    }

    /// Directories whose `*.dylib` files must be visible to `gz-launch` / plugins on macOS.
    static func harmonicDylibSearchPaths() -> [String] {
        var paths: [String] = []
        func append(_ path: String) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
            guard !paths.contains(path) else { return }
            paths.append(path)
        }
        if let root = resolvedRootURL() {
            append(root.appendingPathComponent("lib", isDirectory: true).path)
        }
        for prefix in [homebrewInstallPrefixURL(), developerInstallPrefixURL()].compactMap({ $0 }) {
            append(prefix.appendingPathComponent("lib", isDirectory: true).path)
        }
        for base in ["/opt/homebrew", "/usr/local"] {
            append(URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("lib", isDirectory: true).path)
        }
        return paths
    }

    static let websocketServerPluginInstallHint =
        "Install the Gazebo websocket plugin: brew install libwebsockets && brew reinstall gz-launch7, then run make gazebo-runtime from the Guardian repo."

    /// Default smoke world shipped in the resource bundle.
    static func bundledEmptyWorldURL() -> URL? {
        guard let res = Bundle.module.resourceURL else { return nil }
        let world = res
            .appendingPathComponent(bundleResourceName, isDirectory: true)
            .appendingPathComponent("worlds/guardian_empty.sdf", isDirectory: false)
        return FileManager.default.isReadableFile(atPath: world.path) ? world : nil
    }
}

enum GazeboLaunchRecipe {
    /// Merges DYLD_LIBRARY_PATH and GZ_LAUNCH_PLUGIN_PATH for child `gz` processes.
    static func augmentGazeboProcessEnvironment(_ env: inout [String: String]) {
        let libDirs = GazeboLocator.harmonicDylibSearchPaths()
        if !libDirs.isEmpty {
            let inherited = env["DYLD_LIBRARY_PATH"] ?? ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] ?? ""
            let merged = (libDirs + (inherited.isEmpty ? [] : [inherited])).joined(separator: ":")
            env["DYLD_LIBRARY_PATH"] = merged
        }

        if let root = GazeboLocator.resolvedRootURL() {
            let share = root.appendingPathComponent("share", isDirectory: true).path
            if FileManager.default.fileExists(atPath: share) {
                env["GZ_SIM_RESOURCE_PATH"] = share
            }
        }

        let pluginDirs = GazeboLocator.gzLaunchPluginDirectories().map(\.path)
        guard !pluginDirs.isEmpty else { return }
        let existing = env["GZ_LAUNCH_PLUGIN_PATH"] ?? ProcessInfo.processInfo.environment["GZ_LAUNCH_PLUGIN_PATH"] ?? ""
        let parts = pluginDirs + (existing.isEmpty ? [] : [existing])
        env["GZ_LAUNCH_PLUGIN_PATH"] = parts.joined(separator: ":")
    }

    private static let sessionLogRoot: URL = {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("guardian-gazebo-runtime", isDirectory: true)
            .appendingPathComponent("pid-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base
    }()

    static func runtimeRootPath() -> String? {
        GazeboLocator.resolvedRootURL()?.path
    }

    static func websocketPort(forInstanceIndex instanceIndex: Int) -> Int {
        9002 + instanceIndex
    }

    /// Isolates each `gz sim` + websocket bridge pair on gz-transport (required when more than one instance runs).
    static func transportPartition(forInstanceIndex instanceIndex: Int) -> String {
        "guardian_gz_\(instanceIndex)"
    }

    static func applyTransportPartition(_ partition: String, to env: inout [String: String]) {
        env["GZ_PARTITION"] = partition
        // Legacy alias still read by some Harmonic 7.x tooling.
        env["IGN_PARTITION"] = partition
        // Loopback discovery: macOS often blocks multicast ("No route to host") between
        // `gz sim -s` and the gz-launch websocket plugin on the same machine.
        env["GZ_IP"] = "127.0.0.1"
        env["IGN_IP"] = "127.0.0.1"
    }

    static func bundledWebsocketLaunchTemplateURL() -> URL? {
        guard let root = GazeboLocator.resolvedRootURL() else { return nil }
        let url = root
            .appendingPathComponent("share/gz/gz-launch7/configs/websocket.gzlaunch", isDirectory: false)
        return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }

    /// Writes a websocket launch file with the requested port (from the bundled template when present).
    static func writeWebsocketLaunchFile(port: Int, instanceIndex: Int) throws -> URL {
        let dir = sessionLogRoot.appendingPathComponent("launch-\(instanceIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("guardian_websocket_\(port).gzlaunch", isDirectory: false)
        if let template = bundledWebsocketLaunchTemplateURL() {
            let raw = try String(contentsOf: template, encoding: .utf8)
            let patched = raw.replacingOccurrences(
                of: "<port>9002</port>",
                with: "<port>\(port)</port>"
            )
            try patched.write(to: dest, atomically: true, encoding: .utf8)
        } else {
            let xml = """
            <?xml version='1.0'?>
            <gz version='1.0'>
              <plugin name='gz::launch::WebsocketServer'
                      filename='gz-launch-websocket-server'>
                <publication_hz>30</publication_hz>
                <port>\(port)</port>
                <max_connections>-1</max_connections>
              </plugin>
            </gz>
            """
            try xml.write(to: dest, atomically: true, encoding: .utf8)
        }
        return dest
    }

    /// `gz launch` for the Harmonic websocket server plugin (pairs with `gz sim -s`).
    static func websocketLaunchSpec(
        port: Int,
        instanceIndex: Int,
        launchFileURL: URL
    ) throws -> GazeboProcessSpec {
        guard GazeboLocator.gzExecutablePath() != nil else {
            throw GazeboError.missingRuntime
        }
        let logDir = sessionLogRoot.appendingPathComponent("websocket-\(instanceIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        var env: [String: String] = [:]
        augmentGazeboProcessEnvironment(&env)
        applyTransportPartition(transportPartition(forInstanceIndex: instanceIndex), to: &env)
        env["GUARDIAN_GAZEBO_WEBSOCKET_PORT"] = "\(port)"
        env["GUARDIAN_GAZEBO_INSTANCE"] = "\(instanceIndex)"

        // Invoke `gz-launch` directly — `gz launch` delegates to a shim that may lack rpaths when
        // Guardian strips the parent environment; Harmonic libs live under `<prefix>/lib`.
        let executable: String
        let arguments: [String]
        if let gzLaunch = GazeboLocator.gzLaunchExecutablePath() {
            executable = gzLaunch
            arguments = ["-v", "3", launchFileURL.path]
        } else if let gz = GazeboLocator.gzExecutablePath() {
            executable = gz
            arguments = ["launch", "-v", "3", launchFileURL.path]
        } else {
            throw GazeboError.missingRuntime
        }

        return GazeboProcessSpec(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: logDir,
            environment: env,
            worldPath: launchFileURL.path,
            logDirectoryURL: logDir
        )
    }

    /// Launch `gz sim` for a world SDF. `headless` uses server-only mode (no GUI).
    static func simSpec(
        worldURL: URL,
        instanceIndex: Int,
        headless: Bool = false,
        purpose: GazeboSessionPurpose = .preview
    ) throws -> GazeboProcessSpec {
        guard let gz = GazeboLocator.gzExecutablePath() else {
            throw GazeboError.missingRuntime
        }
        let worldPath = worldURL.path
        guard FileManager.default.isReadableFile(atPath: worldPath) else {
            throw GazeboError.missingWorldFile(worldPath)
        }

        let logDir = sessionLogRoot.appendingPathComponent("world-\(instanceIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        var args = ["sim", "-r", "-v", "3", worldPath]
        if headless {
            args.insert("-s", at: 1)
        }

        var env: [String: String] = [:]
        augmentGazeboProcessEnvironment(&env)
        applyTransportPartition(transportPartition(forInstanceIndex: instanceIndex), to: &env)
        env["GUARDIAN_GAZEBO_WORLD"] = worldPath
        env["GUARDIAN_GAZEBO_INSTANCE"] = "\(instanceIndex)"
        env["GUARDIAN_GAZEBO_PURPOSE"] = purpose.rawValue

        return GazeboProcessSpec(
            executable: gz,
            arguments: args,
            currentDirectoryURL: logDir,
            environment: env,
            worldPath: worldPath,
            logDirectoryURL: logDir
        )
    }
}
