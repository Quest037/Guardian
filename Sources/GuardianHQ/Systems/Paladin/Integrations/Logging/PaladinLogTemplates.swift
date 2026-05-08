import Combine
import Foundation

// MARK: - Stable template ids (future i18n / string tables)

/// Namespace of stable keys for Paladin log lines. `PaladinEvent.message` remains the default English;
/// when a string table maps `templateKey` → pattern, `PaladinLogTemplateRegistry` formats the displayed line.
enum PaladinLogTemplateKey {
    // Fleet mirror (from `FleetLinkService` → Paladin)
    static let fleetMirrorMissionProgress = "fleet.mirror.mission_progress"
    static let fleetMirrorMissionRunComplete = "fleet.mirror.mission_run_complete"
    static let fleetMirrorVehicleStatus = "fleet.mirror.vehicle_status"

    // Execution
    static let executionStarted = "paladin.execution.started"
    static let executionMissionMissing = "paladin.execution.mission_missing_store"

    // Compile
    static let compileSummary = "paladin.compile.summary"
    static let sessionStaging = "paladin.session.staging"

    // Schedule / cycle
    static let scheduleLoopNextIn = "paladin.schedule.loop_next_in"
    static let scheduleOneOffDeferred = "paladin.schedule.one_off_deferred"
    static let scheduleOneOffPostponed = "paladin.schedule.one_off_postponed"
    static let scheduleOneOffStartedImmediately = "paladin.schedule.one_off_started_immediately"
    static let scheduleContinuousRestart = "paladin.schedule.continuous_restart"
    static let scheduleSkipNoMission = "paladin.schedule.skip_no_mission"
    static let scheduleLoopIntermissionSkipped = "paladin.schedule.loop_intermission_skipped"
    static let scheduleLoopIntermissionExtended = "paladin.schedule.loop_intermission_extended"
    /// First mission upload/start for a path is delayed after execution begins (``PathStartDelay``).
    static let schedulePathMissionStartDeferred = "paladin.schedule.path_mission_start_deferred"
    static let schedulePathMissionStartSkipped = "paladin.schedule.path_mission_start_skipped"
    static let schedulePathMissionStartExtended = "paladin.schedule.path_mission_start_extended"

    // Run completion
    static let runStoppedImmediate = "paladin.run.stopped_immediate"
    static let runOneOffFinished = "paladin.run.one_off_finished"
    static let runGracefulAfterCycle = "paladin.run.graceful_after_cycle"
    static let runLoopAllRepeatsDone = "paladin.run.loop_all_repeats_done"

    // Telemetry narrative
    static let telemetryAutopilotSnapshot = "paladin.telemetry.autopilot_snapshot"
    static let telemetryFlightModeChange = "paladin.telemetry.flight_mode_change"
    static let telemetryArmed = "paladin.telemetry.armed"
    static let telemetryDisarmed = "paladin.telemetry.disarmed"
    static let telemetryAirborne = "paladin.telemetry.airborne"
    static let telemetryOnGround = "paladin.telemetry.on_ground"
    static let telemetryAltTrend = "paladin.telemetry.alt_trend"
    static let telemetryTrack = "paladin.telemetry.track"
    static let telemetryApproachWP1 = "paladin.telemetry.approach_wp1"
    static let telemetryTurningLeg = "paladin.telemetry.turning_leg"
    static let telemetryMovingWP1 = "paladin.telemetry.moving_wp1"

    // Commands / fleet
    static let commandInvalidToken = "paladin.command.invalid_token"
    static let commandVehicleUnavailable = "paladin.command.vehicle_unavailable"
    static let commandDispatched = "paladin.command.dispatched"
    static let commandNotSent = "paladin.command.not_sent"
    static let fleetAckSuccess = "paladin.fleet.ack_success"
    static let fleetAckFailed = "paladin.fleet.ack_failed"

    // Staging / mission passes
    static let stagingPassStarted = "paladin.staging.pass_started"
    static let stagingPassComplete = "paladin.staging.pass_complete"
    static let stagingNoToken = "paladin.staging.no_token"
    static let stagingSimFoldedMission = "paladin.staging.sim_folded_mission"
    static let stagingSimTarget = "paladin.staging.sim_target"
    static let stagingSimNoOverride = "paladin.staging.sim_no_override"
    static let stagingLiveReadonly = "paladin.staging.live_readonly"
    static let missionNotStarted = "paladin.mission.not_started"
    static let missionExecuting = "paladin.mission.executing"
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

    func resolveDisplayBody(for event: PaladinEvent) -> String {
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
