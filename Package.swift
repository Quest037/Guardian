// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GuardianHQ",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "GuardianHQ", targets: ["GuardianHQ"]),
    ],
    dependencies: [
        .package(path: "Vendor/MAVSDK-Swift"),
    ],
    targets: [
        .executableTarget(
            name: "GuardianHQ",
            dependencies: [
                .product(name: "Mavsdk", package: "MAVSDK-Swift"),
            ],
            path: "Sources/GuardianHQ",
            exclude: [
                "Plugins/PLUGIN_FLEET_CONTRIBUTIONS.md",
                "Plugins/Paladin/Paladin_README.md",
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/mavsdk_server"),
                .copy("Resources/MavsdkBridge"),
                .copy("Resources/SitlDeps"),
                .copy("Resources/ArduPilotSitl"),
                .copy("Resources/Px4SitlBundle"),
                .copy("Resources/SimulationDevices"),
                .copy("Resources/MissionBadge"),
                .copy("Resources/FleetCalibrationAnchors.json"),
                .copy("Systems/Fleet/Subsystems/Calibration/CalibrationBodies"),
                .copy("Systems/Fleet/Subsystems/Errors/ErrorBodies"),
                .copy("Systems/Fleet/Subsystems/Mission/MissionBodies"),
                .copy("Resources/SitlDefaultParams/ArduPilotGuardianBattery.parm"),
                .copy("Resources/sidebar_logo.png"),
                .copy("Resources/Brand/GuardianMark.svg"),
                .copy("Resources/Brand/GuardianWordmark.svg"),
            ],
            swiftSettings: [
                // Xcode’s Debug configuration does not imply `DEBUG` for SwiftPM targets unless declared here,
                // so `#if DEBUG` (e.g. MC‑R map tap tracing) is compiled out and `Logger` never runs.
                .define("DEBUG", .when(configuration: .debug)),
            ],
            linkerSettings: [
                // Embed a minimal Info.plist so NSBundle has a main bundle identifier
                // when running as a SwiftPM executable in Xcode.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/GuardianHQ/MainBundle-Info.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "GuardianHQTests",
            dependencies: ["GuardianHQ"],
            path: "Tests/GuardianHQTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
