import Foundation

/// World Builder embedded 3D panel (headless `gz sim -s` + websocket + ``GazeboWebViewportView``).
struct GazeboEmbeddedViewportState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case starting
        case live
        case failed(String)
    }

    let worldID: UUID
    let websocketPort: Int
    /// SDF `<world name="…">` — passed to gzweb when the websocket `worlds` handshake is empty.
    let gazeboWorldName: String
    var phase: Phase
}
