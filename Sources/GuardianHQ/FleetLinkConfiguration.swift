import Foundation

/// Persisted settings for MAVSDK Server and default MAVLink ingress.
struct FleetLinkConfiguration: Codable, Equatable, Sendable {
    /// gRPC port exposed by `mavsdk_server` for Swift / clients.
    var grpcPort: Int
    /// Absolute path to `mavsdk_server`; empty uses bundled binary (release), then `MAVSDK_SERVER`, then Homebrew.
    var mavsdkServerPath: String
    /// Primary MAVSDK connection string (e.g. `udpin://0.0.0.0:14550` for GCS-style listen on all interfaces).
    var primaryMavlinkConnectionURL: String
    /// Extra connection strings appended to the server CLI (SITL `udpout://`, serial, etc.).
    var additionalMavlinkConnectionURLs: [String]

    static let defaults = FleetLinkConfiguration(
        grpcPort: 50051,
        mavsdkServerPath: "",
        primaryMavlinkConnectionURL: "udpin://0.0.0.0:14550",
        additionalMavlinkConnectionURLs: []
    )
}

enum FleetLinkError: LocalizedError {
    case invalidExecutable(String)
    case mavsdkServerNotFound
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidExecutable(let path):
            return "mavsdk_server path is not executable: \(path)"
        case .mavsdkServerNotFound:
            return "mavsdk_server not found. For development run ./scripts/fetch_mavsdk_server.sh (or `make`), set MAVSDK_SERVER, install via Homebrew, or set an explicit path under Settings → MAVSDK Server."
        case .startFailed(let detail):
            return detail
        }
    }
}

enum MavsdkServerLocator {
    static func resolveExecutable(configuredPath: String) throws -> String {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if FileManager.default.isExecutableFile(atPath: trimmed) { return trimmed }
            throw FleetLinkError.invalidExecutable(trimmed)
        }
        if let env = ProcessInfo.processInfo.environment["MAVSDK_SERVER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        if let bundled = bundledMavsdkServerPath(), FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        for candidate in ["/opt/homebrew/bin/mavsdk_server", "/usr/local/bin/mavsdk_server"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw FleetLinkError.mavsdkServerNotFound
    }

    /// Universal binary shipped in `GuardianHQ_GuardianHQ.bundle` (see `scripts/fetch_mavsdk_server.sh`).
    private static func bundledMavsdkServerPath() -> String? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "mavsdk_server", withExtension: nil),
            Bundle.module.url(forResource: "mavsdk_server", withExtension: ""),
        ]
        for case let url? in candidates {
            let path = url.path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
