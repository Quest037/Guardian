import Combine
import Foundation

// MARK: - Stable template ids (future i18n / string tables)

/// Stable keys for **fleet-mirrored** Paladin log lines (see ``PaladinFleetMirrorLineClassifier``).
/// Mission Run / Mission Control events use ``MissionRunLogTemplateKey`` instead.
enum PaladinLogTemplateKey {
    static let fleetMirrorMissionProgress = "fleet.mirror.mission_progress"
    static let fleetMirrorMissionRunComplete = "fleet.mirror.mission_run_complete"
    static let fleetMirrorVehicleStatus = "fleet.mirror.vehicle_status"
}

// MARK: - Fleet mirror line → key + params

enum PaladinFleetMirrorLineClassifier {
    private static let missionProgressRE = try! NSRegularExpression(
        pattern: #"^Autopilot mission progress: item (\d+) of (\d+)\.$"#
    )
    private static let missionRunCompleteRE = try! NSRegularExpression(
        pattern: #"^Autopilot mission run complete \(progress (\d+)/(\d+)\); notifying schedule\.$"#
    )
    private static let vehicleStatusRE = try! NSRegularExpression(
        pattern: #"^Vehicle message \[([^\]]+)\]: (.*)$"#
    )

    /// Classifies mirrored fleet log lines so Paladin can localize them later via `templateKey` + `templateParams`.
    static func classify(_ rawLine: String) -> (templateKey: String?, params: [String: String], message: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if let m = missionProgressRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let cur = substring(line, m, 1),
           let tot = substring(line, m, 2) {
            return (PaladinLogTemplateKey.fleetMirrorMissionProgress, ["current": cur, "total": tot], line)
        }

        if let m = missionRunCompleteRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let cur = substring(line, m, 1),
           let tot = substring(line, m, 2) {
            return (PaladinLogTemplateKey.fleetMirrorMissionRunComplete, ["current": cur, "total": tot], line)
        }

        if let m = vehicleStatusRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let label = substring(line, m, 1),
           let text = substring(line, m, 2) {
            return (PaladinLogTemplateKey.fleetMirrorVehicleStatus, ["label": label, "text": text], line)
        }

        return (nil, [:], line)
    }

    private static func substring(_ s: String, _ match: NSTextCheckingResult, _ idx: Int) -> String? {
        guard match.numberOfRanges > idx, let r = Range(match.range(at: idx), in: s) else { return nil }
        return String(s[r])
    }
}

// MARK: - Template registry (optional overrides; default is `event.message`)

@MainActor
final class PaladinLogTemplateRegistry: ObservableObject {
    static let shared = PaladinLogTemplateRegistry()

    /// Localized or custom format patterns using `{{param}}` placeholders (e.g. `"Item {{current}} / {{total}}"`).
    @Published private(set) var templates: [String: String] = [:]

    private init() {}

    func setTemplates(_ entries: [String: String]) {
        var copy = templates
        copy.merge(entries) { _, new in new }
        templates = copy
    }

    func setTemplate(_ key: String, pattern: String) {
        var copy = templates
        copy[key] = pattern
        templates = copy
    }

    func removeTemplate(forKey key: String) {
        var copy = templates
        copy.removeValue(forKey: key)
        templates = copy
    }

    func clearTemplates() {
        templates = [:]
    }

    func resolveDisplayBody(for event: MissionRunEvent) -> String {
        guard let key = event.templateKey,
              let pattern = templates[key],
              !pattern.isEmpty
        else {
            return event.message
        }
        return Self.interpolate(pattern, params: event.templateParams)
    }

    private static func interpolate(_ pattern: String, params: [String: String]) -> String {
        var result = pattern
        for (k, v) in params {
            result = result.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return result
    }
}

extension MissionRunEvent {
    /// Plain line for copy / print (no colours). Uses `PaladinLogTemplateRegistry`
    /// when a `templateKey` pattern is registered.
    @MainActor
    func plainTextLine(
        templateRegistry: PaladinLogTemplateRegistry = .shared,
        mission: Mission? = nil,
        assignments: [MissionRunAssignment] = []
    ) -> String {
        let body = templateRegistry.resolveDisplayBody(for: self)
        let taskNameForPrefix = resolvedTaskLogPrefix(mission: mission, assignments: assignments)
        let pathPart = taskNameForPrefix.map { "[\($0)]" } ?? ""
        let speakerPart: String
        switch speaker {
        case .missionControl: speakerPart = "[MissionControl]"
        case .paladin: speakerPart = "[Paladin]"
        case .vehicleSlot(let slot): speakerPart = "[\(slot)]"
        }
        let prefix = pathPart.isEmpty ? speakerPart : "\(pathPart)\(speakerPart)"
        let sevSuffix: String
        switch level {
        case .info: sevSuffix = ""
        case .warning: sevSuffix = " · warn"
        case .error: sevSuffix = " · error"
        }
        return "\(prefix) \(body)\(sevSuffix)"
    }
}
