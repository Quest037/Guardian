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
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/mavsdk_server"),
                .copy("Resources/MavsdkBridge"),
                .copy("Resources/SitlDeps"),
                .copy("Resources/ArduPilotSitl"),
                .copy("Resources/Px4SitlBundle"),
                .copy("Resources/SimulationDevices"),
                .copy("Resources/SitlDefaultParams/ArduPilotGuardianBattery.parm"),
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
    ]
)
