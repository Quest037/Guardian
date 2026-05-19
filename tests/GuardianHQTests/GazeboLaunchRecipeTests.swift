import XCTest
@testable import GuardianHQ

@MainActor
final class GazeboLaunchRecipeTests: XCTestCase {
    func test_simSpec_buildsGzSimArguments() throws {
        let world = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-test-world-\(UUID().uuidString).sdf")
        try "<?xml version=\"1.0\" ?><sdf version=\"1.9\"><world name=\"t\"></world></sdf>"
            .write(to: world, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: world) }

        guard GazeboLocator.gzExecutablePath() != nil else {
            throw XCTSkip("Gazebo runtime not staged (make gazebo-runtime).")
        }

        let spec = try GazeboLaunchRecipe.simSpec(
            worldURL: world,
            instanceIndex: 3,
            headless: true,
            purpose: .run
        )
        XCTAssertTrue(spec.executable.hasSuffix("/gz") || spec.executable.hasSuffix("/bin/gz"))
        XCTAssertEqual(spec.arguments.prefix(4), ["sim", "-s", "-r", "-v"])
        XCTAssertEqual(spec.arguments.last, world.path)
        XCTAssertEqual(spec.environment["GUARDIAN_GAZEBO_INSTANCE"], "3")
        XCTAssertEqual(spec.environment["GZ_PARTITION"], GazeboLaunchRecipe.transportPartition(forInstanceIndex: 3))
        XCTAssertEqual(spec.environment["GZ_IP"], "127.0.0.1")
        XCTAssertEqual(spec.environment["GUARDIAN_GAZEBO_WORLD"], world.path)
        XCTAssertEqual(spec.environment["GUARDIAN_GAZEBO_PURPOSE"], GazeboSessionPurpose.run.rawValue)
    }

    func test_gazeboConcurrency_envOverride() {
        XCTAssertEqual(
            GazeboConcurrency.resolveMaxConcurrent([GazeboConcurrency.envKey: "5"]),
            5
        )
        XCTAssertEqual(
            GazeboConcurrency.resolveMaxConcurrent([GazeboConcurrency.envKey: "0"]),
            GazeboConcurrency.defaultMaxConcurrentWorlds
        )
        XCTAssertEqual(
            GazeboConcurrency.resolveMaxConcurrent([GazeboConcurrency.envKey: "99"]),
            GazeboConcurrency.resolvedCap
        )
    }

    func test_bundledEmptyWorldURL_whenResourcePresent() {
        guard GazeboLocator.gzExecutablePath() != nil else {
            throw XCTSkip("Gazebo runtime not staged.")
        }
        XCTAssertNotNil(GazeboLocator.bundledEmptyWorldURL())
    }

    func test_websocketPort_offsetsByInstance() {
        XCTAssertEqual(GazeboLaunchRecipe.websocketPort(forInstanceIndex: 0), 9002)
        XCTAssertEqual(GazeboLaunchRecipe.websocketPort(forInstanceIndex: 2), 9004)
    }

    func test_writeWebsocketLaunchFile_containsPort() throws {
        let url = try GazeboLaunchRecipe.writeWebsocketLaunchFile(port: 9010, instanceIndex: 99)
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains("<port>9010</port>"))
    }

    func test_embeddedViewportPolicy_usesServerOnlyForBuilder() {
        XCTAssertTrue(GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: .preview))
        XCTAssertTrue(GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: .build))
        XCTAssertFalse(GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: .run))
        XCTAssertTrue(GazeboSessionLaunchPolicy.headless(for: .preview))
    }

    func test_websocketLaunchSpec_usesGzLaunchWhenPresent() throws {
        guard GazeboLocator.gzExecutablePath() != nil else {
            throw XCTSkip("Gazebo runtime not staged.")
        }
        let launchURL = try GazeboLaunchRecipe.writeWebsocketLaunchFile(port: 9011, instanceIndex: 12)
        let spec = try GazeboLaunchRecipe.websocketLaunchSpec(
            port: 9011,
            instanceIndex: 12,
            launchFileURL: launchURL
        )
        if let gzLaunch = GazeboLocator.gzLaunchExecutablePath() {
            XCTAssertEqual(spec.executable, gzLaunch)
            XCTAssertEqual(spec.arguments.prefix(2), ["-v", "3"])
        } else {
            XCTAssertTrue(spec.arguments.first == "launch")
        }
        XCTAssertNotNil(spec.environment["DYLD_LIBRARY_PATH"])
        XCTAssertFalse(spec.environment["DYLD_LIBRARY_PATH"]?.isEmpty ?? true)
        XCTAssertEqual(spec.environment["GZ_PARTITION"], GazeboLaunchRecipe.transportPartition(forInstanceIndex: 12))
        XCTAssertEqual(spec.environment["GZ_IP"], "127.0.0.1")
    }

    func test_transportPartition_isStablePerInstance() {
        XCTAssertEqual(GazeboLaunchRecipe.transportPartition(forInstanceIndex: 0), "guardian_gz_0")
        XCTAssertEqual(GazeboLaunchRecipe.transportPartition(forInstanceIndex: 2), "guardian_gz_2")
    }

    func test_augmentGazeboProcessEnvironment_setsLaunchPluginPathWhenDirsExist() throws {
        guard GazeboLocator.gzExecutablePath() != nil else {
            throw XCTSkip("Gazebo runtime not staged.")
        }
        let dirs = GazeboLocator.gzLaunchPluginDirectories()
        guard !dirs.isEmpty else {
            throw XCTSkip("No gz-launch plugin directories in staged runtime.")
        }
        var env: [String: String] = [:]
        GazeboLaunchRecipe.augmentGazeboProcessEnvironment(&env)
        XCTAssertNotNil(env["GZ_LAUNCH_PLUGIN_PATH"])
        XCTAssertTrue(env["GZ_LAUNCH_PLUGIN_PATH"]?.contains(dirs[0].path) == true)
    }

    func test_websocketPluginAvailability_matchesFilesystem() {
        let expected = GazeboLocator.websocketServerPluginURL() != nil
        XCTAssertEqual(GazeboLocator.isWebsocketServerPluginAvailable, expected)
    }
}
