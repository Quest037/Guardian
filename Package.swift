// swift-tools-version: 6.0
import PackageDescription

func guardianExecutableLinkerSettings(infoPlistPath: String) -> [LinkerSetting] {
    [
        .unsafeFlags([
            "-Xlinker", "-sectcreate",
            "-Xlinker", "__TEXT",
            "-Xlinker", "__info_plist",
            "-Xlinker", infoPlistPath,
        ], .when(platforms: [.macOS])),
    ]
}

let package = Package(
    name: "GuardianHQ",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "GuardianHQ", targets: ["GuardianHQ"]),
        .executable(name: "GuardianHQ", targets: ["GuardianHQRun"]),
        .executable(name: "GuardianMission", targets: ["GuardianMission"]),
        .executable(name: "GuardianTraining", targets: ["GuardianTraining"]),
    ],
    dependencies: [
        .package(path: "Vendor/MAVSDK-Swift"),
    ],
    targets: [
        .target(
            name: "GuardianHQ",
            dependencies: [
                .product(name: "Mavsdk", package: "MAVSDK-Swift"),
            ],
            path: "Sources/GuardianHQ",
            exclude: [
                "Plugins/PLUGIN_FLEET_CONTRIBUTIONS.md",
                "Plugins/Paladin/Paladin_README.md",
                "MainBundle-Info.plist",
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/mavsdk_server"),
                .copy("Resources/MavsdkBridge"),
                .copy("Resources/Ros2VehicleBridge"),
                .copy("Resources/Ros2AutonomyStacks"),
                .copy("Resources/Ros2Runtime"),
                .copy("Resources/SitlDeps"),
                .copy("Resources/ArduPilotSitl"),
                .copy("Resources/Px4SitlBundle"),
                .copy("Resources/GazeboRuntime"),
                .copy("Resources/GazeboWeb"),
                .copy("Resources/TrainingEnvironments"),
                .copy("Resources/Px4SitlMavlink"),
                .copy("Resources/SimulationDevices"),
                .copy("Resources/MissionBadge"),
                .copy("Resources/FleetCalibrationAnchors.json"),
                .copy("Systems/Fleet/Subsystems/Calibration/CalibrationBodies"),
                .copy("Systems/Fleet/Subsystems/Errors/ErrorBodies"),
                .copy("Systems/Fleet/Subsystems/Mission/MissionBodies"),
                .copy("Resources/SitlDefaultParams/ArduPilotGuardianBattery.parm"),
                .copy("Resources/sidebar_logo.png"),
                .copy("Resources/sidebar_logo_training.png"),
                .copy("Resources/splash_logo_mission.png"),
                .copy("Resources/splash_logo_training.png"),
                .copy("Resources/dock_logo_mission.png"),
                .copy("Resources/dock_logo_training.png"),
                .copy("Resources/Brand/GuardianMark.svg"),
                .copy("Resources/Brand/GuardianWordmark.svg"),
            ],
            swiftSettings: [
                // Xcode’s Debug configuration does not imply `DEBUG` for SwiftPM targets unless declared here,
                // so `#if DEBUG` (e.g. MC‑R map tap tracing) is compiled out and `Logger` never runs.
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "GuardianHQRun",
            dependencies: ["GuardianHQ"],
            path: "Sources/Apps/GuardianHQRun",
            exclude: ["MainBundle-Info.plist"],
            linkerSettings: guardianExecutableLinkerSettings(
                infoPlistPath: "Sources/Apps/GuardianHQRun/MainBundle-Info.plist"
            )
        ),
        .executableTarget(
            name: "GuardianMission",
            dependencies: ["GuardianHQ"],
            path: "Sources/Apps/GuardianMission",
            exclude: ["MainBundle-Info.plist"],
            linkerSettings: guardianExecutableLinkerSettings(
                infoPlistPath: "Sources/Apps/GuardianMission/MainBundle-Info.plist"
            )
        ),
        .executableTarget(
            name: "GuardianTraining",
            dependencies: ["GuardianHQ"],
            path: "Sources/Apps/GuardianTraining",
            exclude: ["MainBundle-Info.plist"],
            linkerSettings: guardianExecutableLinkerSettings(
                infoPlistPath: "Sources/Apps/GuardianTraining/MainBundle-Info.plist"
            )
        ),
        .testTarget(
            name: "GuardianHQTests",
            dependencies: [
                "GuardianHQ",
                .product(name: "Mavsdk", package: "MAVSDK-Swift"),
            ],
            path: "Tests/GuardianHQTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
