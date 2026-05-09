import Foundation

@MainActor
final class MissionRunLoggingSubsystem {
    private struct VehicleVoiceSnapshot: Equatable {
        var flightMode: String
        var isArmed: Bool
        var relativeAltM: Double?
        var latitudeDeg: Double?
        var longitudeDeg: Double?
        var inAir: Bool?
        var lastTrackLogAt: Date?
        var lastTrackLoggedLat: Double?
        var lastTrackLoggedLon: Double?
        var lastAltTrendLogAt: Date?
        var lastRouteProgressLogAt: Date?
        var announcedApproachWP1: Bool
    }

    weak var environment: MissionRunEnvironment?
    private var taskContextByAssignmentID: [UUID: (taskID: UUID?, taskLabel: String?)] = [:]
    private var vehicleVoiceSnapshots: [UUID: VehicleVoiceSnapshot] = [:]

    func appendLogEvent(
        level: MissionRunEventLevel,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        environment?.appendEvent(
            MissionRunEvent(
                level: level,
                taskID: taskID,
                taskLabel: taskLabel,
                speaker: speaker,
                message: message,
                templateKey: templateKey,
                templateParams: templateParams
            )
        )
    }

    func setTaskContextFromRoleTracks(_ tracks: [MissionControlRoleTrack]) {
        var context: [UUID: (taskID: UUID?, taskLabel: String?)] = [:]
        for track in tracks {
            context[track.assignmentID] = (track.taskID, track.taskDisplayName)
        }
        taskContextByAssignmentID = context
    }

    func taskContextForAssignment(_ assignmentID: UUID) -> (UUID?, String?) {
        let ctx = taskContextByAssignmentID[assignmentID] ?? (nil, nil)
        return (ctx.taskID, ctx.taskLabel)
    }

    /// Task id/label for log lines: role-track context when compiled, otherwise roster ``MissionRunAssignment/taskId`` or single enabled task.
    func effectiveTaskFields(forAssignmentID assignmentID: UUID) -> (UUID?, String?) {
        let fromTracks = taskContextForAssignment(assignmentID)
        if fromTracks.0 != nil || !(fromTracks.1 ?? "").isEmpty {
            return fromTracks
        }
        guard let environment, let mission = environment.template,
              let a = environment.assignments.first(where: { $0.id == assignmentID })
        else {
            return fromTracks
        }
        if let tid = a.taskId,
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           !task.name.isEmpty {
            return (tid, task.name)
        }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, let only = enabled.first, !only.name.isEmpty {
            return (only.id, only.name)
        }
        return (nil, nil)
    }

    func clearState() {
        vehicleVoiceSnapshots.removeAll()
        taskContextByAssignmentID.removeAll()
    }

    func appendFleetMirrorLine(
        vehicleID: String,
        line: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment else { return }
        guard environment.status == .running || environment.status == .paused else { return }
        guard environment.sessionPhase == .executing else { return }
        guard let assignment = environment.assignments.first(where: {
            resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == vehicleID
        }) else { return }
        let level: MissionRunEventLevel
        if line.contains("[CRITICAL]") || line.contains("[ERROR]")
            || line.contains("[EMERGENCY]") || line.contains("[ALERT]") {
            level = .error
        } else if line.contains("[WARN]") {
            level = .warning
        } else {
            level = .info
        }
        let fields = effectiveTaskFields(forAssignmentID: assignment.id)
        let classified = PaladinFleetMirrorLineClassifier.classify(line)
        appendLogEvent(
            level: level,
            taskID: fields.0,
            taskLabel: fields.1,
            speaker: .vehicleSlot(assignment.slotName),
            message: classified.message,
            templateKey: classified.templateKey,
            templateParams: classified.params
        )
    }

    func ingestVehicleTelemetryNarrative(
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment else { return }
        guard environment.status == .running || environment.status == .paused else { return }
        guard environment.sessionPhase == .executing else { return }
        for assignment in environment.assignments {
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            else { continue }
            let slot = assignment.slotName
            let taskFields = effectiveTaskFields(forAssignmentID: assignment.id)
            let prev = vehicleVoiceSnapshots[assignment.id]
            var lastTrack = prev?.lastTrackLogAt
            var lastTrackLoggedLat = prev?.lastTrackLoggedLat
            var lastTrackLoggedLon = prev?.lastTrackLoggedLon
            var lastAlt = prev?.lastAltTrendLogAt
            var lastRoute = prev?.lastRouteProgressLogAt
            var announcedWP = prev?.announcedApproachWP1 ?? false
            if prev == nil {
                let mode = hub.flightMode.isEmpty ? "unknown" : hub.flightMode
                let arm = hub.isArmed ? "armed" : "disarmed"
                let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "-"
                appendLogEvent(
                    level: .info,
                    taskID: taskFields.0,
                    taskLabel: taskFields.1,
                    speaker: .vehicleSlot(slot),
                    message: "Autopilot: mode \(mode), \(arm), rel alt \(alt).",
                    templateKey: MissionRunLogTemplateKey.telemetryAutopilotSnapshot,
                    templateParams: ["mode": mode, "armState": arm, "relAlt": alt]
                )
            } else if prev!.flightMode != hub.flightMode, !hub.flightMode.isEmpty {
                appendLogEvent(
                    level: .info,
                    taskID: taskFields.0,
                    taskLabel: taskFields.1,
                    speaker: .vehicleSlot(slot),
                    message: "Flight mode: \(prev!.flightMode) -> \(hub.flightMode).",
                    templateKey: MissionRunLogTemplateKey.telemetryFlightModeChange,
                    templateParams: ["from": prev!.flightMode, "to": hub.flightMode]
                )
            } else if prev!.isArmed != hub.isArmed {
                appendLogEvent(
                    level: .info,
                    taskID: taskFields.0,
                    taskLabel: taskFields.1,
                    speaker: .vehicleSlot(slot),
                    message: hub.isArmed ? "Armed." : "Disarmed.",
                    templateKey: hub.isArmed ? MissionRunLogTemplateKey.telemetryArmed : MissionRunLogTemplateKey.telemetryDisarmed
                )
            } else if let was = prev!.inAir, let now = hub.inAir, was != now {
                appendLogEvent(
                    level: .info,
                    taskID: taskFields.0,
                    taskLabel: taskFields.1,
                    speaker: .vehicleSlot(slot),
                    message: now ? "Airborne." : "On ground (in-air flag cleared).",
                    templateKey: now ? MissionRunLogTemplateKey.telemetryAirborne : MissionRunLogTemplateKey.telemetryOnGround
                )
            }
            if let r = hub.relativeAltM, let prevAlt = prev?.relativeAltM {
                let delta = r - prevAlt
                let since = lastAlt.map { Date().timeIntervalSince($0) } ?? 100
                if abs(delta) >= 2.5, since >= 4 {
                    let trend = delta > 0 ? "Climbing" : "Descending"
                    appendLogEvent(
                        level: .info,
                        taskID: taskFields.0,
                        taskLabel: taskFields.1,
                        speaker: .vehicleSlot(slot),
                        message: "\(trend) - rel alt ~\(String(format: "%.1f", r)) m (delta \(String(format: "%.1f", delta)) m).",
                        templateKey: MissionRunLogTemplateKey.telemetryAltTrend,
                        templateParams: ["trend": trend, "alt": String(format: "%.1f", r), "delta": String(format: "%.1f", delta)]
                    )
                    lastAlt = Date()
                }
            }
            if let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
                if lastTrackLoggedLat == nil || lastTrackLoggedLon == nil {
                    lastTrackLoggedLat = lat
                    lastTrackLoggedLon = lon
                } else if let refLat = lastTrackLoggedLat, let refLon = lastTrackLoggedLon {
                    let moved = MissionTelemetryGeo.horizontalDistanceM(lat1: refLat, lon1: refLon, lat2: lat, lon2: lon)
                    if moved >= 12 {
                        let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "-"
                        let mode = hub.flightMode.isEmpty ? "-" : hub.flightMode
                        appendLogEvent(
                            level: .info,
                            taskID: taskFields.0,
                            taskLabel: taskFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Track - \(String(format: "%.5f", lat)) deg, \(String(format: "%.5f", lon)) deg · rel alt \(alt) · \(mode).",
                            templateKey: MissionRunLogTemplateKey.telemetryTrack,
                            templateParams: ["lat": String(format: "%.5f", lat), "lon": String(format: "%.5f", lon), "relAlt": alt, "mode": mode]
                        )
                        lastTrackLoggedLat = lat
                        lastTrackLoggedLon = lon
                        lastTrack = Date()
                    }
                }
            }
            if let mission,
               let wp = Self.firstMissionWaypoint(for: assignment, mission: mission),
               let lat = hub.latitudeDeg,
               let lon = hub.longitudeDeg,
               let heading = hub.headingDeg ?? hub.yawDeg {
                let dist = MissionTelemetryGeo.horizontalDistanceM(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let bear = MissionTelemetryGeo.bearingDegrees(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let turn = abs(MissionTelemetryGeo.angleDifferenceDeg(heading, bear))
                let sinceR = lastRoute.map { Date().timeIntervalSince($0) } ?? 100
                if !announcedWP, dist < 38 {
                    let mode = hub.flightMode.isEmpty ? "-" : hub.flightMode
                    appendLogEvent(
                        level: .info,
                        taskID: taskFields.0,
                        taskLabel: taskFields.1,
                        speaker: .vehicleSlot(slot),
                        message: "Approaching first waypoint - ~\(Int(dist)) m out, mode \(mode).",
                        templateKey: MissionRunLogTemplateKey.telemetryApproachWP1,
                        templateParams: ["distance": String(Int(dist)), "mode": mode]
                    )
                    announcedWP = true
                    lastRoute = Date()
                } else if sinceR >= 12 {
                    if turn > 28, dist > 22 {
                        appendLogEvent(
                            level: .info,
                            taskID: taskFields.0,
                            taskLabel: taskFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Turning toward leg - heading ~\(Int(heading)) deg, bearing to WP1 ~\(Int(bear)) deg (~\(Int(dist)) m).",
                            templateKey: MissionRunLogTemplateKey.telemetryTurningLeg,
                            templateParams: ["heading": String(Int(heading)), "bearing": String(Int(bear)), "distance": String(Int(dist))]
                        )
                        lastRoute = Date()
                    } else if dist > 45 {
                        appendLogEvent(
                            level: .info,
                            taskID: taskFields.0,
                            taskLabel: taskFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Moving toward WP1 - ~\(Int(dist)) m, aligned within ~\(Int(turn)) deg.",
                            templateKey: MissionRunLogTemplateKey.telemetryMovingWP1,
                            templateParams: ["distance": String(Int(dist)), "turn": String(Int(turn))]
                        )
                        lastRoute = Date()
                    }
                }
            }
            vehicleVoiceSnapshots[assignment.id] = VehicleVoiceSnapshot(
                flightMode: hub.flightMode,
                isArmed: hub.isArmed,
                relativeAltM: hub.relativeAltM,
                latitudeDeg: hub.latitudeDeg ?? prev?.latitudeDeg,
                longitudeDeg: hub.longitudeDeg ?? prev?.longitudeDeg,
                inAir: hub.inAir ?? prev?.inAir,
                lastTrackLogAt: lastTrack,
                lastTrackLoggedLat: lastTrackLoggedLat ?? prev?.lastTrackLoggedLat,
                lastTrackLoggedLon: lastTrackLoggedLon ?? prev?.lastTrackLoggedLon,
                lastAltTrendLogAt: lastAlt,
                lastRouteProgressLogAt: lastRoute,
                announcedApproachWP1: announcedWP
            )
        }
    }

    private static func firstMissionWaypoint(for assignment: MissionRunAssignment, mission: Mission) -> RouteCoordinate? {
        if let pid = assignment.taskId,
           let task = mission.routeMacro.tasks.first(where: { $0.id == pid }),
           let coord = task.waypoints.first?.coord {
            return coord
        }
        if let task = mission.routeMacro.tasks.first(where: { $0.enabled }),
           let coord = task.waypoints.first?.coord {
            return coord
        }
        return mission.routeMacro.tasks.first?.waypoints.first?.coord
    }
}

// MARK: - Log template keys (vehicle telemetry narrative)

extension MissionRunLogTemplateKey {
    static let telemetryAutopilotSnapshot = "missioncontrol.mre.telemetry.autopilot_snapshot"
    static let telemetryFlightModeChange = "missioncontrol.mre.telemetry.flight_mode_change"
    static let telemetryArmed = "missioncontrol.mre.telemetry.armed"
    static let telemetryDisarmed = "missioncontrol.mre.telemetry.disarmed"
    static let telemetryAirborne = "missioncontrol.mre.telemetry.airborne"
    static let telemetryOnGround = "missioncontrol.mre.telemetry.on_ground"
    static let telemetryAltTrend = "missioncontrol.mre.telemetry.alt_trend"
    static let telemetryTrack = "missioncontrol.mre.telemetry.track"
    static let telemetryApproachWP1 = "missioncontrol.mre.telemetry.approach_wp1"
    static let telemetryTurningLeg = "missioncontrol.mre.telemetry.turning_leg"
    static let telemetryMovingWP1 = "missioncontrol.mre.telemetry.moving_wp1"
}

