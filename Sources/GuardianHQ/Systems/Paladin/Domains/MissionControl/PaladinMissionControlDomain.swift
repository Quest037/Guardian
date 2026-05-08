import Foundation
import Mavsdk

enum PaladinSessionPhase: String, Equatable {
    case draft
    case compiled
    /// Plan is ready; waiting for a scheduled execution instant (e.g. one-off future start) before staging/mission passes run.
    case staging
    case executing
    case completed
    case failed
}

enum PaladinPathTopology: String, Equatable {
    case singlePath
    case multiPath
}

enum PaladinTeamTopology: String, Equatable {
    case singleVehiclePerPath
    case multiVehicleTeam
}

enum PaladinWorkPartitionMode: String, Equatable {
    case pathOwned
    case segmentOwned
    case waypointOwned
}

enum PaladinHandoffMode: String, Equatable {
    case none
    case thresholdDriven
    case scheduled
}

enum PaladinEventLevel: String, Equatable {
    case info
    case warning
    case error
}

/// Who produced the log line: Paladin planner vs a roster slot (callsign).
enum PaladinLogSpeaker: Equatable {
    case paladin
    case vehicleSlot(String)
}

/// Resolves route path id + display name for bracket tags (e.g. `[Dagger]`).
enum PaladinPathTagName {
    static func pathContext(for assignment: MissionRunAssignment, mission: Mission?) -> (id: UUID, label: String)? {
        guard let mission else { return nil }
        if let pid = assignment.pathId,
           let path = mission.routeMacro.paths.first(where: { $0.id == pid }) {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.paths.first(where: { $0.enabled }) {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.paths.first {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        return nil
    }
}

struct PaladinVehicleBinding: Equatable {
    let tokenKey: String
    let title: String
    let vehicleIDText: String
    let status: VehicleLifecycleStatus
}

struct PaladinRoleTrack: Identifiable, Equatable {
    let id: UUID
    let pathID: UUID?
    /// Route path name for log tags; mirrors `pathID` at compile time.
    let pathDisplayName: String?
    let assignmentID: UUID
    let rosterDeviceID: UUID
    let slotName: String
    let boundVehicle: PaladinVehicleBinding?
}

struct PaladinPlan: Equatable {
    let missionID: UUID
    let runID: UUID
    let missionName: String
    let scheduleMode: MissionRunScheduleMode
    let loopIntervalMinutes: Int
    let loopRepeatCount: Int
    let createdAt: Date
    let pathTopology: PaladinPathTopology
    let teamTopology: PaladinTeamTopology
    let workPartitionMode: PaladinWorkPartitionMode
    let handoffMode: PaladinHandoffMode
    let roleTracks: [PaladinRoleTrack]
}

struct PaladinEvent: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let level: PaladinEventLevel
    /// Route path id (map tint); optional when mission-wide.
    let pathID: UUID?
    /// Path name for `[Name]` tag and plain-text export.
    let pathLabel: String?
    let speaker: PaladinLogSpeaker
    /// Default English (or raw vehicle text); used when no template override is registered for `templateKey`.
    let message: String
    /// Stable id for future localization / string tables (`{{param}}` in patterns).
    let templateKey: String?
    let templateParams: [String: String]

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        level: PaladinEventLevel = .info,
        pathID: UUID? = nil,
        pathLabel: String? = nil,
        speaker: PaladinLogSpeaker = .paladin,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        self.id = id
        self.at = at
        self.level = level
        self.pathID = pathID
        self.pathLabel = pathLabel
        self.speaker = speaker
        self.message = message
        self.templateKey = templateKey
        self.templateParams = templateParams
    }

    /// Plain line for copy / print (no colours). Uses `PaladinLogTemplateRegistry` when a `templateKey` pattern is registered.
    @MainActor
    func plainTextLine(templateRegistry: PaladinLogTemplateRegistry = .shared) -> String {
        let body = templateRegistry.resolveDisplayBody(for: self)
        let pathPart = pathLabel.map { "[\($0)]" } ?? ""
        let speakerPart: String
        switch speaker {
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

struct PaladinSession: Identifiable, Equatable {
    let id: UUID
    let runID: UUID
    let missionID: UUID
    var phase: PaladinSessionPhase
    let plan: PaladinPlan
    var events: [PaladinEvent]
    let createdAt: Date

    init(id: UUID = UUID(), runID: UUID, missionID: UUID, phase: PaladinSessionPhase, plan: PaladinPlan, events: [PaladinEvent], createdAt: Date = Date()) {
        self.id = id
        self.runID = runID
        self.missionID = missionID
        self.phase = phase
        self.plan = plan
        self.events = events
        self.createdAt = createdAt
    }
}

struct PaladinIssuedCommand: Identifiable, Equatable {
    let id: UUID
    let assignmentID: UUID
    let slotName: String
    let vehicleTokenKey: String
    let command: FleetVehicleCommand
    let source: String
    let category: FleetVehicleCommandCategory

    init(
        id: UUID = UUID(),
        assignmentID: UUID,
        slotName: String,
        vehicleTokenKey: String,
        command: FleetVehicleCommand,
        source: String,
        category: FleetVehicleCommandCategory = .paladin
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.slotName = slotName
        self.vehicleTokenKey = vehicleTokenKey
        self.command = command
        self.source = source
        self.category = category
    }
}

struct PaladinRuntimePassResult: Equatable {
    var events: [PaladinEvent]
    var commands: [PaladinIssuedCommand]
}

// MARK: - MAVLink mission bridge (template → MAVSDK Mission plugin)

enum PaladinMavlinkMissionBuilder {
    /// MAVLink mission for **one** enabled path with exactly one assigned fleet vehicle and ≥1 waypoint.
    static func buildDronePathMission(
        run: MissionRun,
        mission: Mission,
        pathId: UUID
    ) -> (
        assignment: MissionRunAssignment,
        items: [Mavsdk.Mission.MissionItem]
    )? {
        guard let path = mission.routeMacro.paths.first(where: { $0.id == pathId && $0.enabled }),
              !path.waypoints.isEmpty
        else { return nil }

        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        let assignmentsForPath = run.assignments.filter { assignment in
            if assignment.pathId == path.id { return true }
            if assignment.pathId == nil, enabledPaths.count == 1 { return true }
            return false
        }
        guard assignmentsForPath.count == 1,
              let assignment = assignmentsForPath.first,
              assignment.attachedFleetVehicleToken != nil
        else { return nil }

        let home = mission.routeMacro.home
        var items: [Mavsdk.Mission.MissionItem] = []

        if let staging = assignment.simStartOverrideCoord, let firstWP = path.waypoints.first {
            items.append(
                mavItem(
                    coord: staging,
                    waypoint: firstWP,
                    home: home,
                    useWaypointHeadingForYaw: true
                )
            )
        }

        for (index, wp) in path.waypoints.enumerated() {
            let ignoreDelay = shouldIgnoreClosingWaypointDelay(path: path, index: index, waypoint: wp)
            items.append(
                mavItem(
                    coord: wp.coord,
                    waypoint: wp,
                    home: home,
                    useWaypointHeadingForYaw: true,
                    loiterOverrideSeconds: ignoreDelay ? 0 : nil
                )
            )
        }

        return (assignment, items)
    }

    /// One enabled path in the template; same as ``buildDronePathMission(run:mission:pathId:)`` for that path.
    static func buildSingleDronePathMission(run: MissionRun, mission: Mission) -> (
        assignment: MissionRunAssignment,
        items: [Mavsdk.Mission.MissionItem]
    )? {
        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        guard enabledPaths.count == 1, let only = enabledPaths.first else { return nil }
        return buildDronePathMission(run: run, mission: mission, pathId: only.id)
    }

    /// Enabled route path that Paladin’s MAVLink mission is built from, plus uploaded mission item count (for live progress UI).
    static func mavlinkMissionProgressContext(
        run: MissionRun,
        mission: Mission
    ) -> (path: RoutePath, missionItemCount: Int)? {
        guard let (assignment, items) = buildSingleDronePathMission(run: run, mission: mission) else {
            return nil
        }
        let path: RoutePath?
        if let pid = assignment.pathId {
            path = mission.routeMacro.paths.first { $0.id == pid }
        } else {
            let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
            path = enabledPaths.count == 1 ? enabledPaths.first : nil
        }
        guard let path else { return nil }
        return (path, items.count)
    }

    private static func mavItem(
        coord: RouteCoordinate,
        waypoint: RouteWaypoint,
        home: RouteHome?,
        useWaypointHeadingForYaw: Bool,
        loiterOverrideSeconds: Float? = nil
    ) -> Mavsdk.Mission.MissionItem {
        let relAlt = relativeAltitudeM(waypoint: waypoint, home: home)
        let speed = speedMetersPerSecond(waypoint: waypoint)
        let loiter = loiterOverrideSeconds ?? delaySeconds(waypoint: waypoint)
        let yaw: Float = useWaypointHeadingForYaw ? Float(waypoint.heading) : 0

        return Mavsdk.Mission.MissionItem(
            latitudeDeg: coord.lat,
            longitudeDeg: coord.lon,
            relativeAltitudeM: relAlt,
            speedMS: speed,
            isFlyThrough: false,
            gimbalPitchDeg: 0,
            gimbalYawDeg: 0,
            cameraAction: .none,
            loiterTimeS: loiter,
            cameraPhotoIntervalS: 0,
            acceptanceRadiusM: 3,
            yawDeg: yaw,
            cameraPhotoDistanceM: 0
        )
    }

    private static func relativeAltitudeM(waypoint: RouteWaypoint, home: RouteHome?) -> Float {
        let v = waypoint.altitude.value
        switch waypoint.altitude.reference {
        case .agl:
            return Float(max(5, v))
        case .msl, .asl:
            let homeAlt = home?.altitude.value ?? 0
            return Float(max(5, v - homeAlt))
        }
    }

    private static func speedMetersPerSecond(waypoint: RouteWaypoint) -> Float {
        let t = waypoint.transition
        let s = t.targetSpeed
        switch t.speedUnit {
        case .metersPerSecond:
            return Float(max(1, s))
        case .kilometersPerHour:
            return Float(max(1, s / 3.6))
        }
    }

    private static func delaySeconds(waypoint: RouteWaypoint) -> Float {
        switch waypoint.delayUnit {
        case .secs:
            return Float(max(0, waypoint.delaySec))
        case .mins:
            return Float(max(0, waypoint.delaySec * 60))
        case .hrs:
            return Float(max(0, waypoint.delaySec * 3600))
        }
    }

    /// Closed loop with duplicated end/start: if the final waypoint has no action, treat it as structural return and ignore delay.
    private static func shouldIgnoreClosingWaypointDelay(path: RoutePath, index: Int, waypoint: RouteWaypoint) -> Bool {
        guard path.waypoints.count >= 2, index == path.waypoints.count - 1 else { return false }
        guard let first = path.waypoints.first else { return false }
        guard waypointHasNoAction(waypoint) else { return false }
        return coordinatesNearlyEqual(first.coord, waypoint.coord)
    }

    private static func waypointHasNoAction(_ waypoint: RouteWaypoint) -> Bool {
        let normalized = waypoint.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "none"
    }

    private static func coordinatesNearlyEqual(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Bool {
        let epsilon = 0.0000001
        return abs(a.lat - b.lat) <= epsilon && abs(a.lon - b.lon) <= epsilon
    }
}

enum PaladinCompiler {
    @MainActor
    static func compile(
        run: MissionRun,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) -> PaladinPlan {
        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        let pathTopology: PaladinPathTopology = enabledPaths.count <= 1 ? .singlePath : .multiPath

        var boundByToken: [String: MissionPickableFleetVehicle] = [:]
        for vehicle in fleetVehicles {
            boundByToken[vehicle.token.storageKey] = vehicle
        }

        let roleTracks: [PaladinRoleTrack] = run.assignments.map { assignment in
            let boundVehicle = assignment.attachedFleetVehicleToken.flatMap { token in
                boundByToken[token].map { vehicle in
                    PaladinVehicleBinding(
                        tokenKey: token,
                        title: vehicle.title,
                        vehicleIDText: vehicle.vehicleIDText,
                        status: vehicle.lifecycleStatus
                    )
                }
            }
            let ctx = PaladinPathTagName.pathContext(for: assignment, mission: mission)
            return PaladinRoleTrack(
                id: UUID(),
                pathID: ctx?.id ?? assignment.pathId,
                pathDisplayName: ctx?.label,
                assignmentID: assignment.id,
                rosterDeviceID: assignment.rosterDeviceId,
                slotName: assignment.slotName,
                boundVehicle: boundVehicle
            )
        }

        let roleCountByPath = Dictionary(grouping: roleTracks, by: \.pathID).mapValues(\.count)
        let hasTeamPath = roleCountByPath.values.contains { $0 > 1 }
        let teamTopology: PaladinTeamTopology = hasTeamPath ? .multiVehicleTeam : .singleVehiclePerPath

        let workPartitionMode: PaladinWorkPartitionMode = hasTeamPath ? .segmentOwned : .pathOwned
        let handoffMode: PaladinHandoffMode = run.paladinTightCycleHandoff ? .thresholdDriven : .none

        return PaladinPlan(
            missionID: mission.id,
            runID: run.id,
            missionName: run.missionName,
            scheduleMode: run.scheduleMode,
            loopIntervalMinutes: run.loopIntervalMinutes,
            loopRepeatCount: run.loopRepeatCount,
            createdAt: Date(),
            pathTopology: pathTopology,
            teamTopology: teamTopology,
            workPartitionMode: workPartitionMode,
            handoffMode: handoffMode,
            roleTracks: roleTracks
        )
    }
}

enum PaladinRuntime {
    /// When true, Paladin will run a MAVLink mission for this template/run; skip separate staging `goto` to avoid racing `upload/arm/start`.
    private static func skipsStagingRelocateBecauseMissionWillRun(run: MissionRun, mission: Mission?) -> Bool {
        guard let mission else { return false }
        return PaladinMavlinkMissionBuilder.buildSingleDronePathMission(run: run, mission: mission) != nil
    }

    /// First executable pass: validate and apply setup-stage assumptions before mission execution.
    /// Returns event stream entries that the UI can render immediately in the live console.
    @MainActor
    static func executeStagingPass(run: MissionRun, mission: Mission?) -> PaladinRuntimePassResult {
        var events: [PaladinEvent] = []
        var commands: [PaladinIssuedCommand] = []
        events.append(
            PaladinEvent(
                level: .info,
                message: "Paladin staging pass started.",
                templateKey: PaladinLogTemplateKey.stagingPassStarted
            )
        )
        let skipRelocate = skipsStagingRelocateBecauseMissionWillRun(run: run, mission: mission)

        for assignment in run.assignments {
            let slot = assignment.slotName
            let pc = PaladinPathTagName.pathContext(for: assignment, mission: mission)
            let pathID = pc?.id
            let pathLabel = pc?.label
            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey)
            else {
                events.append(
                    PaladinEvent(
                        level: .warning,
                        pathID: pathID,
                        pathLabel: pathLabel,
                        speaker: .paladin,
                        message: "No fleet vehicle token; skipping staging.",
                        templateKey: PaladinLogTemplateKey.stagingNoToken
                    )
                )
                continue
            }

            switch token {
            case .sitl:
                if let coord = assignment.simStartOverrideCoord {
                    if !skipRelocate {
                        commands.append(
                            PaladinIssuedCommand(
                                assignmentID: assignment.id,
                                slotName: slot,
                                vehicleTokenKey: tokenKey,
                                command: .gotoCoordinate(coord, relativeAltitudeM: 20, yawDeg: 0),
                                source: "paladin.staging",
                                category: .paladin
                            )
                        )
                    } else if skipRelocate {
                        events.append(
                            PaladinEvent(
                                level: .info,
                                pathID: pathID,
                                pathLabel: pathLabel,
                                speaker: .paladin,
                                message: "SIM staging location folded into MAVLink mission (no separate goto).",
                                templateKey: PaladinLogTemplateKey.stagingSimFoldedMission
                            )
                        )
                    }
                    events.append(
                        PaladinEvent(
                            level: .info,
                            pathID: pathID,
                            pathLabel: pathLabel,
                            speaker: .paladin,
                            message: String(
                                format: "SIM staging target set to %.6f, %.6f.",
                                coord.lat,
                                coord.lon
                            ),
                            templateKey: PaladinLogTemplateKey.stagingSimTarget,
                            templateParams: [
                                "lat": String(format: "%.6f", coord.lat),
                                "lon": String(format: "%.6f", coord.lon),
                            ]
                        )
                    )
                } else {
                    events.append(
                        PaladinEvent(
                            level: .warning,
                            pathID: pathID,
                            pathLabel: pathLabel,
                            speaker: .paladin,
                            message: "SIM has no staging override; default spawn position will be used.",
                            templateKey: PaladinLogTemplateKey.stagingSimNoOverride
                        )
                    )
                }
            case .live:
                events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pathID,
                        pathLabel: pathLabel,
                        speaker: .paladin,
                        message: "Live vehicle staging is telemetry-driven (read-only).",
                        templateKey: PaladinLogTemplateKey.stagingLiveReadonly
                    )
                )
            }
        }

        events.append(
            PaladinEvent(
                level: .info,
                message: "Paladin staging pass complete (\(run.assignments.count) slot(s) evaluated).",
                templateKey: PaladinLogTemplateKey.stagingPassComplete,
                templateParams: ["slotCount": String(run.assignments.count)]
            )
        )
        return PaladinRuntimePassResult(events: events, commands: commands)
    }

    /// Upload mission + arm + start for the vehicle assigned to **`pathId`**, or the sole enabled path when **`pathId`** is `nil`.
    @MainActor
    static func executePrimaryMissionPass(
        run: MissionRun,
        mission: Mission,
        pathId: UUID? = nil
    ) -> PaladinRuntimePassResult {
        var events: [PaladinEvent] = []
        var commands: [PaladinIssuedCommand] = []

        let resolvedPathId: UUID? = {
            if let pathId { return pathId }
            let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
            return enabledPaths.count == 1 ? enabledPaths.first?.id : nil
        }()

        guard let pid = resolvedPathId,
              let built = PaladinMavlinkMissionBuilder.buildDronePathMission(run: run, mission: mission, pathId: pid),
              let tokenKey = built.assignment.attachedFleetVehicleToken
        else {
            events.append(
                PaladinEvent(
                    level: .warning,
                    message: "MAVLink mission not started (need one enabled path, one assigned vehicle, ≥1 waypoint).",
                    templateKey: PaladinLogTemplateKey.missionNotStarted
                )
            )
            return PaladinRuntimePassResult(events: events, commands: commands)
        }

        let pc = PaladinPathTagName.pathContext(for: built.assignment, mission: mission)
        events.append(
            PaladinEvent(
                level: .info,
                pathID: pc?.id,
                pathLabel: pc?.label,
                speaker: .paladin,
                message: "Executing MAVLink mission for “\(built.assignment.slotName)” (\(built.items.count) item(s)).",
                templateKey: PaladinLogTemplateKey.missionExecuting,
                templateParams: [
                    "slot": built.assignment.slotName,
                    "itemCount": String(built.items.count),
                ]
            )
        )
        commands.append(
            PaladinIssuedCommand(
                assignmentID: built.assignment.id,
                slotName: built.assignment.slotName,
                vehicleTokenKey: tokenKey,
                command: .uploadAndStartMission(items: built.items),
                source: "paladin.mission",
                category: .paladin
            )
        )
        return PaladinRuntimePassResult(events: events, commands: commands)
    }
}
