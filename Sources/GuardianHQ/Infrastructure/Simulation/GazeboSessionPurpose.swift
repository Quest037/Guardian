import Foundation

/// Why Guardian started a `gz sim` process — drives Simulate gate and launch options.
enum GazeboSessionPurpose: String, Codable, Sendable, CaseIterable {
    /// World Builder: live edit session (GUI sim; Simulate off).
    case build
    /// World Builder: inspect a saved package (GUI sim; Simulate off).
    case preview
    /// Training / Formation: operational run (Simulate on).
    case run
}

enum GazeboSessionLaunchPolicy {
    static func requiresSimulateEnabled(for purpose: GazeboSessionPurpose) -> Bool {
        switch purpose {
        case .build, .preview:
            return false
        case .run:
            return true
        }
    }

    /// World Builder embedded panel: headless physics server + websocket bridge (not a separate GUI window).
    static func usesEmbeddedWebViewport(for purpose: GazeboSessionPurpose) -> Bool {
        switch purpose {
        case .build, .preview:
            return true
        case .run:
            return false
        }
    }

    static func headless(for purpose: GazeboSessionPurpose) -> Bool {
        usesEmbeddedWebViewport(for: purpose)
    }

    static func logLabel(for purpose: GazeboSessionPurpose) -> String {
        switch purpose {
        case .build: return "build"
        case .preview: return "preview"
        case .run: return "run"
        }
    }
}
