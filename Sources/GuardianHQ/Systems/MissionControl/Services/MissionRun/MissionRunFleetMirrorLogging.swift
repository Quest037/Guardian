import Foundation

// MARK: - Fleet mirror → mission run log (template ids)

/// Stable ``MissionRunEvent/templateKey`` values for lines mirrored from ``FleetLinkService`` into an active mission run.
enum FleetMirrorLogTemplateKey {
    static let fleetMirrorMissionProgress = "fleet.mirror.mission_progress"
    static let fleetMirrorMissionRunComplete = "fleet.mirror.mission_run_complete"
    static let fleetMirrorVehicleStatus = "fleet.mirror.vehicle_status"
    /// Line did not match a known pattern; body uses ``templateParams`` key `text`.
    static let fleetMirrorUnclassified = "fleet.mirror.unclassified"
}

// MARK: - Classifier

/// Regex-based classifier for known autopilot / vehicle message shapes on mirrored fleet lines.
enum FleetMirrorLineClassifier {
    private static let missionProgressRE = try! NSRegularExpression(
        pattern: #"^Autopilot mission progress: item (\d+) of (\d+)\.$"#
    )
    private static let missionRunCompleteRE = try! NSRegularExpression(
        pattern: #"^Autopilot mission run complete \(progress (\d+)/(\d+)\); notifying schedule\.$"#
    )
    private static let vehicleStatusRE = try! NSRegularExpression(
        pattern: #"^Vehicle message \[([^\]]+)\]: (.*)$"#
    )

    /// Returns a catalog ``templateKey`` + ``templateParams`` when matched; otherwise `templateKey == nil` and raw text as `message`.
    static func classify(_ rawLine: String) -> (templateKey: String?, params: [String: String], message: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if let m = missionProgressRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let cur = substring(line, m, 1),
           let tot = substring(line, m, 2) {
            return (FleetMirrorLogTemplateKey.fleetMirrorMissionProgress, ["current": cur, "total": tot], line)
        }

        if let m = missionRunCompleteRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let cur = substring(line, m, 1),
           let tot = substring(line, m, 2) {
            return (FleetMirrorLogTemplateKey.fleetMirrorMissionRunComplete, ["current": cur, "total": tot], line)
        }

        if let m = vehicleStatusRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let label = substring(line, m, 1),
           let text = substring(line, m, 2) {
            return (FleetMirrorLogTemplateKey.fleetMirrorVehicleStatus, ["label": label, "text": text], line)
        }

        return (nil, [:], line)
    }

    private static func substring(_ s: String, _ match: NSTextCheckingResult, _ idx: Int) -> String? {
        guard match.numberOfRanges > idx, let r = Range(match.range(at: idx), in: s) else { return nil }
        return String(s[r])
    }
}
