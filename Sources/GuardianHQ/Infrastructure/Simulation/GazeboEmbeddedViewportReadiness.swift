import Foundation

/// Strips ANSI color / reset sequences from Gazebo child log lines before pattern matching.
enum GazeboChildLogLine {
    static func plain(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
    }
}

/// Parses gz-launch websocket plugin stderr for bind / scene handshake failures.
@MainActor
final class GazeboWebsocketBridgeLogTracker {
    private(set) var serverBindFailed = false
    private(set) var sceneInfoQueryFailed = false

    func consume(_ line: String) {
        let plain = GazeboChildLogLine.plain(line)
        if plain.contains("Unable to create websocket server") {
            serverBindFailed = true
        }
        if plain.contains("Failed to get the scene information") {
            sceneInfoQueryFailed = true
        }
    }

    func resetForRetry() {
        serverBindFailed = false
        sceneInfoQueryFailed = false
    }
}

/// Tracks `gz sim -s` logs until scene topics are published (embedded web viewport).
@MainActor
final class GazeboSimSceneReadinessTracker {
    private(set) var scenePublishing = false
    private(set) var matchedWorldName: String?

    func consume(_ line: String) {
        let plain = GazeboChildLogLine.plain(line)
        if plain.contains("Publishing scene information") {
            scenePublishing = true
            matchedWorldName = Self.extractWorldName(fromSceneInfoLine: plain) ?? matchedWorldName
            return
        }
        if plain.contains("/scene/info") {
            if plain.localizedCaseInsensitiveContains("publishing")
                || plain.localizedCaseInsensitiveContains("advertis")
                || plain.localizedCaseInsensitiveContains("serving scene") {
                scenePublishing = true
                matchedWorldName = Self.extractWorldName(fromSceneInfoLine: plain) ?? matchedWorldName
            }
            return
        }
        // Harmonic 8.x often logs world init before the scene/info publish line appears.
        if plain.contains("World [") && plain.contains("] initialized with") {
            scenePublishing = true
            matchedWorldName = Self.extractWorldName(fromWorldInitializedLine: plain) ?? matchedWorldName
        }
    }

    static func extractWorldName(fromWorldInitializedLine line: String) -> String? {
        guard let open = line.range(of: "World [") else { return nil }
        let tail = line[open.upperBound...]
        guard let close = tail.firstIndex(of: "]") else { return nil }
        let name = String(tail[..<close])
        return name.isEmpty ? nil : name
    }

    static func extractWorldName(fromSceneInfoLine line: String) -> String? {
        guard let range = line.range(of: "/world/") else { return nil }
        let tail = line[range.upperBound...]
        guard let end = tail.range(of: "/scene/info") else { return nil }
        let name = String(tail[..<end.lowerBound])
        return name.isEmpty ? nil : name
    }
}

/// Confirms `/world/<name>/scene/info` on gz-transport (same partition as sim + websocket).
enum GazeboTransportSceneReadiness {
    static func sceneInfoTopicPath(worldName: String) -> String {
        "/world/\(worldName)/scene/info"
    }

    /// True when `gz topic -i` reports at least one publisher on the scene topic.
    static func sceneInfoTopicHasPublisher(
        worldName: String,
        instanceIndex: Int,
        infoTimeoutMS: Int = 4000
    ) async -> Bool {
        guard let gz = GazeboLocator.gzExecutablePath() else { return false }
        let topic = sceneInfoTopicPath(worldName: worldName)
        let result = await GazeboEntityFactoryClient.runTopicInfoProbe(
            gz: gz,
            instanceIndex: instanceIndex,
            topic: topic,
            timeoutMS: infoTimeoutMS
        )
        guard result.exitCode == 0 else { return false }
        let plain = GazeboChildLogLine.plain(result.stdout + "\n" + result.stderr)
        return plain.contains("Publishers")
            && (plain.contains("gz.msgs.Scene") || plain.contains("ignition.msgs.Scene"))
    }

    /// Polls until scene info has a publisher or the deadline passes.
    static func waitForSceneInfoTopicPublisher(
        worldName: String,
        instanceIndex: Int,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.35
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await sceneInfoTopicHasPublisher(
                worldName: worldName,
                instanceIndex: instanceIndex,
                infoTimeoutMS: min(4000, Int(max(1, deadline.timeIntervalSinceNow) * 1000))
            ) {
                return true
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            try? await Task.sleep(
                nanoseconds: UInt64(min(pollInterval, remaining) * 1_000_000_000)
            )
        }
        return false
    }
}
