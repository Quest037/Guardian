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
    targets: [
        .executableTarget(
            name: "GuardianHQ",
            path: "Sources/GuardianHQ"
        ),
    ]
)
