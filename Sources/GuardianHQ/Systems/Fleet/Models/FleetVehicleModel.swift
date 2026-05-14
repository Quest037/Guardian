import Foundation
import Mavsdk

/// Who is allowed to preempt lower-priority command streams (Mission Control automation, Paladin assistant, free roam, Live Drive takeover).
enum FleetVehicleCommandCategory: String, Equatable, Comparable {
    /// Mission Control run automation (arms, mission starts, staging, teardown) — same authority tier as ``paladin``.
    case missionControl
    /// Paladin assistant–issued fleet commands (same tier as ``missionControl``).
    case paladin
    case freeRoamKeyboard
    case manualTakeover

    /// Higher rejects lower when `commandGateMinimumPriority` is raised.
    var arbitrationPriority: Int {
        switch self {
        case .missionControl, .paladin: return 0
        case .freeRoamKeyboard: return 1
        case .manualTakeover: return 2
        }
    }

    static func < (lhs: FleetVehicleCommandCategory, rhs: FleetVehicleCommandCategory) -> Bool {
        if lhs.arbitrationPriority != rhs.arbitrationPriority {
            return lhs.arbitrationPriority < rhs.arbitrationPriority
        }
        return lhs.rawValue < rhs.rawValue
    }
}

enum FleetVehicleCommand: Equatable {
    case arm
    case disarm
    /// Hold / loiter in place using autopilot action-hold.
    /// Surfaced in the LiveDrive end-session menu as "Loiter" for UAV and "Park" for
    /// UGV/USV/UUV — same underlying autopilot action, class-specific UI label.
    case holdPosition
    case gotoCoordinate(RouteCoordinate, relativeAltitudeM: Double, yawDeg: Double)
    /// Upload a mission plan to the autopilot — atomic upload step only.
    ///
    /// Routes to `Drone.mission.uploadMission(missionPlan:)` followed by
    /// `Drone.mission.setCurrentMissionItem(index: 0)` (resetting the current waypoint
    /// so a re-uploaded plan always starts from item 0). Does **not** arm and does **not** start the mission;
    /// callers compose those as separate commands (`.arm`, plus a future "start mission"
    /// atom). This atom is what `command.fleet.vehicle.do.mission.upload` dispatches.
    case uploadMission(items: [Mavsdk.Mission.MissionItem])
    /// Upload geofence plan to the autopilot (``Geofence/uploadGeofence``). Replaces any prior fence plan for this call.
    ///
    /// Payload mirrors `geofencePolygonsJSON`: MAVSDK ``Geofence/GeofenceData`` polygons plus optional circle primitives
    /// (horizontal geometry only on the fleet wire).
    case uploadGeofence(FleetVehicleCommandGeofenceUploadPayload)
    /// Clear all geofences on the autopilot (``Geofence/clearGeofence``).
    case clearGeofence
    /// Clear the mission plan on the autopilot (`Mission.clearMission()`).
    case missionClear
    /// Start mission execution (`Mission.startMission()`).
    case missionStart
    /// Pause mission execution (`Mission.pauseMission()`).
    case missionPause
    /// Set the current mission item index (`Mission.setCurrentMissionItem(index:)`).
    case missionSetCurrentItem(index: Int32)
    /// Download the mission plan and surface it as JSON (same shape as `missionItemsJSON`).
    case missionDownloadPlanJSON
    /// One-shot read: whether the mission has finished (`Mission.isMissionFinished()`).
    case missionIsFinishedQuery
    /// One-shot read: RTL-after-mission flag (`Mission.getReturnToLaunchAfterMission()`).
    case missionGetRtlAfter
    /// Set RTL-after-mission (`Mission.setReturnToLaunchAfterMission(enable:)`).
    case missionSetRtlAfter(enable: Bool)
    /// Cancel an in-flight mission upload (`Mission.cancelMissionUpload()`).
    case cancelMissionUpload
    /// Cancel an in-flight mission download (`Mission.cancelMissionDownload()`).
    case cancelMissionDownload
    /// Command the autopilot to return to launch / home (MAVSDK Action plugin).
    case returnToLaunch
    /// Command the autopilot to land now (where supported).
    case land
    /// Class-aware **park**: stop safely, disarm, end in hold / loiter (UAV: land if airborne
    /// then disarm then hold; UGV/USV: hold then disarm then hold; UUV: surface if deep
    /// then disarm then hold). Dispatched only via ``FleetLinkService/runParkPipeline`` —
    /// not decomposed into separate catalogue steps so timeouts and telemetry waits stay coherent.
    case park
    /// Stop streaming and switch the autopilot to its "MANUAL" stick-passthrough mode so
    /// the vehicle stops moving but remains immediately controllable. Issued from the
    /// LiveDrive end-session menu for non-flying classes (UGV/USV/UUV) — handy when
    /// Paladin needs to retake the vehicle quickly during a live mission without going
    /// through the full re-arm / mode-engage cycle. Routed via stack-specific shell
    /// command (`commander mode manual` on PX4, `mode manual` on ArduPilot) because
    /// MAVSDK's `Action` plugin has no direct "set MANUAL" helper.
    case idle
    /// High-level manual-control intent routed through FleetLink per vehicle class.
    case manualControl(ManualControlIntentCommand)
    /// Run one of the MAVSDK Calibration plugin procedures end-to-end.
    /// Routed via `Drone.calibration.calibrate*()` which emits an `Observable<ProgressData>`;
    /// `FleetLinkService` bridges that stream into the standard `Completable` outcome shape
    /// (`onCompleted` → `.succeeded`, `onError` → `.failed(detail)`). Progress events are
    /// not yet surfaced — recipes get a single terminal outcome in v1.
    /// PX4-friendly today; raw MAVLink-only calibration atoms use
    /// ``FleetVehicleCommand/mavlinkCommandLong(_:)``.
    case calibrateMavsdk(MavsdkCalibrationKind)
    /// Send one raw MAVLink v2 `COMMAND_LONG` packet. Used for calibration procedures
    /// that are in MAVLink but absent from MAVSDK Swift's generated plugin surface.
    case mavlinkCommandLong(MavlinkCommandLongRequest)
    /// Cancel any MAVSDK Calibration plugin procedure that is currently in flight.
    /// No-op if nothing is running. Routes to `Drone.calibration.cancel()` (Completable).
    case cancelCalibration
    /// Write a single autopilot parameter as a float via MAVSDK Param plugin. Used by
    /// stack converters to implement param-driven "calibrations" (declination, battery
    /// scale, gimbal neutral offsets, …) as a single round-trip.
    case setParameterFloat(name: String, value: Double)
    /// Write a single autopilot parameter as an int32 via MAVSDK Param plugin. Used by
    /// stack converters to implement param-driven "calibrations" with integer-typed
    /// params (battery capacity in mAh, servo PWM endpoints, RC trim values, …).
    case setParameterInt(name: String, value: Int32)
    /// Set the autopilot's flight / drive mode using a real, stack-specific transport.
    /// PX4 dispatches a raw MAVLink `SET_MODE` packet via ``Px4ModeCommander``;
    /// ArduPilot dispatches `mode <name>` via the MAVSDK `Shell` plugin; the
    /// stack-`unknown` path tries the AP shell first and falls back to PX4 raw MAVLink.
    /// Modes that the target stack genuinely cannot honour (e.g. `brake` on PX4) fail
    /// with a `mode not supported` detail so stack converters classify the response as
    /// ``FleetCommandErrorKind/modeNotSupported``.
    case setMode(FleetVehicleMode)
    /// Stop MAVSDK offboard setpoint streaming (`Offboard.stop()`). Catalogue:
    /// `command.fleet.vehicle.do.offboard.stop` — used when recipes must exit offboard
    /// after flows that intentionally keep offboard active (e.g. PX4 UGV operator park).
    case offboardStop
    /// Reboot the autopilot (`MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN`, dispatched via
    /// MAVSDK `Action.reboot()`). Heavy hammer used to clear all transient autopilot
    /// state — sticky pre-arm faults, latched failsafe acks, hung calibrations, etc.
    /// Because MAVLink and MAVSDK do not expose a generic "clear all errors" command,
    /// `command.fleet.vehicle.do.reboot.autopilot` is the closest universal reset; the
    /// recipe layer composes it with re-arm / mode-restore steps after the autopilot
    /// comes back up. Risk-tier `groundOnly` — recipes must never invoke this in a
    /// live mission.
    case rebootAutopilot
}

extension FleetVehicleCommand {
    /// Compact label for mission-run logs and dispatch summaries (Layer‑0 vehicle commands).
    var missionRunDispatchShortLabel: String {
        switch self {
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .holdPosition: return "hold"
        case .gotoCoordinate: return "goto"
        case .uploadMission(let items): return "upload mission (\(items.count) item(s))"
        case .uploadGeofence(let wire):
            return "upload geofence (\(wire.polygons.count) polygon(s), \(wire.circles.count) circle(s))"
        case .clearGeofence: return "clear geofence"
        case .missionClear: return "mission clear"
        case .missionStart: return "mission start"
        case .missionPause: return "mission pause"
        case .missionSetCurrentItem(let index): return "mission set item \(index)"
        case .missionDownloadPlanJSON: return "mission download"
        case .missionIsFinishedQuery: return "mission is finished"
        case .missionGetRtlAfter: return "mission RTL-after read"
        case .missionSetRtlAfter(let enable): return "mission RTL-after set \(enable)"
        case .cancelMissionUpload: return "cancel mission upload"
        case .cancelMissionDownload: return "cancel mission download"
        case .returnToLaunch: return "return to launch"
        case .land: return "land"
        case .park: return "park"
        case .idle: return "idle (manual)"
        case .manualControl(let manual): return "manual \(manual.intent.rawValue)"
        case .calibrateMavsdk(let kind): return "calibrate \(kind.rawValue)"
        case .mavlinkCommandLong(let request): return "mavlink command \(request.command)"
        case .cancelCalibration: return "cancel calibration"
        case .setParameterFloat(let name, _): return "param \(name) (float)"
        case .setParameterInt(let name, _): return "param \(name) (int)"
        case .setMode(let mode): return "set mode \(mode.rawValue)"
        case .offboardStop: return "offboard stop"
        case .rebootAutopilot: return "reboot autopilot"
        }
    }
}

/// Stack-agnostic autopilot mode token. Used by ``FleetVehicleCommand/setMode(_:)``
/// and by the catalogue's `command.fleet.vehicle.do.mode` translation. Each value
/// has a stack-specific implementation in ``FleetLinkService`` — the converter
/// produces this token, the link service does the per-stack SET_MODE dispatch.
///
/// Coverage matrix (v1):
///
/// | Token       | PX4 SET_MODE             | ArduPilot shell                  | Notes                                                |
/// |-------------|--------------------------|----------------------------------|------------------------------------------------------|
/// | `.hold`     | AUTO + AUTO_LOITER (3)   | `mode loiter` / `mode hold`      | AP rover uses `hold`; UAV / UUV use `loiter`         |
/// | `.manual`   | MANUAL                   | `mode manual`                    |                                                      |
/// | `.auto`     | AUTO + AUTO_MISSION (4)  | `mode auto`                      | AP "auto" semantically *is* mission                  |
/// | `.rtl`      | AUTO + AUTO_RTL (5)      | `mode rtl`                       |                                                      |
/// | `.guided`   | OFFBOARD                 | `mode guided`                    | PX4 has no "guided"; OFFBOARD is the closest analogue|
/// | `.mission`  | AUTO + AUTO_MISSION (4)  | `mode auto`                      | Same end-state as `.auto`; reserved for clarity      |
/// | `.landMode` | AUTO + AUTO_LAND (6)     | `mode land`                      |                                                      |
/// | `.brake`    | not supported            | `mode brake` (Copter only)       | PX4 returns `mode not supported`                     |
/// | `.surface`  | not supported            | `mode surface` (Sub only)        | ArduSub mode 9; PX4 has no UUV stack                 |
enum FleetVehicleMode: String, Equatable, Codable, CaseIterable, Sendable {
    case hold
    case manual
    case auto
    case rtl
    case guided
    case mission
    case landMode
    case brake
    /// ArduSub-only "automatically return to surface" mode (mode number 9). PX4 has
    /// no UUV stack; both PX4 and non-Sub ArduPilot firmware reject this mode.
    /// `command.fleet.vehicle.do.surface` is the high-level operator entry point —
    /// recipes can also reach it via `command.fleet.vehicle.do.mode mode=surface`.
    case surface
}

/// Discriminator for `FleetVehicleCommand.calibrateMavsdk(_:)`. Each case maps 1:1 to
/// one of the MAVSDK `Calibration` plugin's `calibrate*()` `Observable<ProgressData>`
/// streams. The set is deliberately limited to what the MAVSDK Swift port exposes today;
/// extra calibrations (baro, ESC, RC, airspeed, compass-motor) require a different
/// transport (raw MAVLink command-long) and stay out of this enum until that lands.
enum MavsdkCalibrationKind: String, Equatable, Codable, CaseIterable {
    case gyro
    case accelerometer
    case magnetometer
    case levelHorizon
    case gimbalAccelerometer
}

/// Progress event emitted by ``FleetLinkService`` while a MAVSDK Calibration plugin
/// procedure is in flight. Layer 1 recipe runners and Layer 2 wizards / plugins
/// subscribe to ``FleetLinkService/calibrationProgressEventsPublisher`` and filter
/// by `vehicleID` (and optionally `kind`).
///
/// A run is terminated by exactly one of the three terminal phases: `.completed`,
/// `.cancelled`, or `.failed(detail:)`. Any number of `.progress` and / or
/// `.operatorPrompt` events may appear before the terminal one.
struct FleetCalibrationProgressEvent: Equatable, Sendable {
    let vehicleID: String
    let kind: MavsdkCalibrationKind
    let phase: Phase
    /// `0...1` while in `.progress`; `nil` for non-progress phases or when the
    /// autopilot did not include a percentage in this MAVSDK ProgressData sample.
    let progressFraction: Double?
    /// Operator-facing instruction extracted from MAVSDK `ProgressData.statusText`
    /// (e.g. `"Hold still"`, `"Rotate vehicle"`). Carried on `.progress` and
    /// `.operatorPrompt` phases when the autopilot supplied one.
    let statusText: String?
    let timestamp: Date

    enum Phase: Equatable, Sendable {
        /// Mid-procedure tick — `progressFraction` and / or `statusText` populated.
        case progress
        /// Mid-procedure tick whose `statusText` is an operator instruction the
        /// autopilot wants surfaced (`hasStatusText && progressFraction == nil`,
        /// or `statusText` matches an "operator action" cue from MAVSDK). The
        /// recipe / wizard layer is responsible for routing this into UI / toast /
        /// UserNotifications surfaces.
        case operatorPrompt
        /// Terminal: the calibration converged successfully.
        case completed
        /// Terminal: the calibration was cancelled mid-flight (`Drone.calibration
        /// .cancel()` was issued or the autopilot self-cancelled).
        case cancelled
        /// Terminal: the calibration failed. `detail` is the raw failure message
        /// surfaced by MAVSDK.
        case failed(detail: String)
    }
}

enum UniversalVehicleClass: String, Equatable, Codable, CaseIterable {
    case uav
    case ugv
    case usv
    case uuv
    case unknown
}

/// Granular vehicle classification used for the canonical short ID shown in logs, cards, and headers
/// (e.g. `UAV-C:1`). Coarser bucket → ``UniversalVehicleClass``.
///
/// Eight first-class types match the airframes Guardian ships SITL presets for:
/// `UAV-C` (multirotor), `UAV-F` (fixed-wing), `UAV-V` (VTOL), `UGV-W` (wheeled), `UGV-T` (tracked),
/// `UGV-L` (legged), `USV` (surface), `UUV` (underwater). `unknown` falls back to the generic `VEH` code.
enum FleetVehicleType: String, Equatable, Codable, CaseIterable, Sendable {
    case uavCopter
    case uavFixedWing
    case uavVTOL
    case ugvWheeled
    case ugvTracked
    case ugvLegged
    case usv
    case uuv
    case unknown

    /// Short class code embedded in `displayShortID` (e.g. `UAV-C`, `USV`, or `VEH` when unknown).
    var classCode: String {
        switch self {
        case .uavCopter: return "UAV-C"
        case .uavFixedWing: return "UAV-F"
        case .uavVTOL: return "UAV-V"
        case .ugvWheeled: return "UGV-W"
        case .ugvTracked: return "UGV-T"
        case .ugvLegged: return "UGV-L"
        case .usv: return "USV"
        case .uuv: return "UUV"
        case .unknown: return "VEH"
        }
    }

    /// Long form shown on info sheets and class settings (e.g. "UAV Copter").
    var displayName: String {
        switch self {
        case .uavCopter: return "UAV Copter"
        case .uavFixedWing: return "UAV Fixed-Wing"
        case .uavVTOL: return "UAV VTOL"
        case .ugvWheeled: return "UGV Wheeled"
        case .ugvTracked: return "UGV Tracked"
        case .ugvLegged: return "UGV Legged"
        case .usv: return "USV (surface)"
        case .uuv: return "UUV (underwater)"
        case .unknown: return "Vehicle"
        }
    }

    /// Coarser arbitration class — used by manual control, command routing, etc.
    var universalClass: UniversalVehicleClass {
        switch self {
        case .uavCopter, .uavFixedWing, .uavVTOL: return .uav
        case .ugvWheeled, .ugvTracked, .ugvLegged: return .ugv
        case .usv: return .usv
        case .uuv: return .uuv
        case .unknown: return .unknown
        }
    }
}

/// Policy for **substituting** one ``FleetVehicleType`` for another (reserve swap-in, roster vacancy fill, automation).
///
/// Locked rules are summarised in **README.md** → **Floating reserve pool** (class substitution row). Extend here when
/// product adds tiers (e.g. USV vs UUV); keep call sites on ``FleetVehicleType/substitutionMatches(required:candidate:policy:)``.
enum FleetVehicleSubstitutionPolicy: String, Equatable, Codable, CaseIterable, Sendable {
    /// Candidate must equal the required granular type. ``unknown`` matches only ``unknown``.
    case exactGranularType
    /// Default for mission-run reserve draw / swap: exact match, plus **UGV-Wheeled ↔ UGV-Tracked** interchange.
    /// UAV kinds (copter / fixed-wing / VTOL), USV, UUV, and legged UGV stay **exact** only.
    case missionRunReserveSwap
}

extension FleetVehicleType {
    /// Whether `candidate` may fill a vacancy that expects `required` under `policy`.
    ///
    /// **Unknown:** If the vacancy’s required type is ``unknown``, substitution is refused (no guess). If the
    /// candidate is ``unknown`` while the vacancy is typed, substitution is refused. Both ``unknown`` matches under
    /// ``FleetVehicleSubstitutionPolicy/exactGranularType`` only (equality).
    static func substitutionMatches(
        required: FleetVehicleType,
        candidate: FleetVehicleType,
        policy: FleetVehicleSubstitutionPolicy
    ) -> Bool {
        switch policy {
        case .exactGranularType:
            return required == candidate
        case .missionRunReserveSwap:
            if required == candidate { return true }
            if required == .unknown || candidate == .unknown { return false }
            return Self.ugvWheeledTrackedPair(required, candidate)
        }
    }

    /// Convenience: `self` is the vacancy’s expected type; `candidate` is the reserve (or bound vehicle) type.
    func substitutionMatches(candidate: FleetVehicleType, policy: FleetVehicleSubstitutionPolicy) -> Bool {
        Self.substitutionMatches(required: self, candidate: candidate, policy: policy)
    }

    private static func ugvWheeledTrackedPair(_ a: FleetVehicleType, _ b: FleetVehicleType) -> Bool {
        switch (a, b) {
        case (.ugvWheeled, .ugvTracked), (.ugvTracked, .ugvWheeled):
            return true
        default:
            return false
        }
    }
}

enum ManualControlIntent: String, Equatable, Codable, CaseIterable {
    case moveForward
    case moveLeft
    case moveBackward
    case moveRight
    case yawLeft
    case yawRight
    case ascend
    case descend
    case toggleArm
    case engage
    case terminate
}

struct ManualControlIntentCommand: Equatable {
    let intent: ManualControlIntent
    let vehicleClass: UniversalVehicleClass
    let stepProfile: ManualControlStepProfile
}

struct ManualControlStepProfile: Equatable, Codable {
    /// Legacy bump distance (m) used by the discrete `gotoLocation` movement path.
    /// Retained for `engage`/recovery actions; superseded for axis input by `max…MS` velocities.
    var moveForwardBackwardM: Double
    var moveLeftRightM: Double
    var yawDeg: Double
    var verticalM: Double

    /// Body-frame forward velocity (m/s) at full keyboard or stick deflection.
    /// Streamed via `Offboard.setVelocityBody` (or scaled into `ManualControl.x` for stick mode).
    var maxForwardMS: Double
    /// Body-frame strafe velocity (m/s, +right) at full deflection.
    var maxStrafeMS: Double
    /// Climb / descent rate (m/s) at full deflection (ascend = positive forward, descend = negative).
    var maxVerticalMS: Double
    /// Yaw rate (deg/s) at full deflection (+right / clockwise viewed from above).
    var maxYawRateDegS: Double

    init(
        moveForwardBackwardM: Double,
        moveLeftRightM: Double,
        yawDeg: Double,
        verticalM: Double,
        maxForwardMS: Double = 1.5,
        maxStrafeMS: Double = 1.5,
        maxVerticalMS: Double = 0.8,
        maxYawRateDegS: Double = 30
    ) {
        self.moveForwardBackwardM = moveForwardBackwardM
        self.moveLeftRightM = moveLeftRightM
        self.yawDeg = yawDeg
        self.verticalM = verticalM
        self.maxForwardMS = maxForwardMS
        self.maxStrafeMS = maxStrafeMS
        self.maxVerticalMS = maxVerticalMS
        self.maxYawRateDegS = maxYawRateDegS
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moveForwardBackwardM = try c.decode(Double.self, forKey: .moveForwardBackwardM)
        moveLeftRightM = try c.decode(Double.self, forKey: .moveLeftRightM)
        yawDeg = try c.decode(Double.self, forKey: .yawDeg)
        verticalM = try c.decode(Double.self, forKey: .verticalM)
        maxForwardMS = try c.decodeIfPresent(Double.self, forKey: .maxForwardMS) ?? 1.5
        maxStrafeMS = try c.decodeIfPresent(Double.self, forKey: .maxStrafeMS) ?? 1.5
        maxVerticalMS = try c.decodeIfPresent(Double.self, forKey: .maxVerticalMS) ?? 0.8
        maxYawRateDegS = try c.decodeIfPresent(Double.self, forKey: .maxYawRateDegS) ?? 30
    }
}

enum FleetVehicleCommandStatus: Equatable {
    case queued
    case sent
    case succeeded
    case failed(String)
}

/// MAVSDK Completable result surfaced to Mission Control and other callers (upload, arm, goto, etc.).
enum FleetCommandAsyncOutcome: Equatable {
    case succeeded
    /// Terminal success with a structured payload (e.g. MAVSDK `Single` mission reads).
    case succeededWithPayload(FleetCommandResponsePayload)
    case failed(String)
}

struct FleetVehicleCommandRecord: Identifiable, Equatable {
    let id: UUID
    let issuedAt: Date
    let source: String
    let category: FleetVehicleCommandCategory
    let command: FleetVehicleCommand
    var status: FleetVehicleCommandStatus

    init(
        id: UUID = UUID(),
        issuedAt: Date = Date(),
        source: String,
        category: FleetVehicleCommandCategory = .missionControl,
        command: FleetVehicleCommand,
        status: FleetVehicleCommandStatus = .queued
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.source = source
        self.category = category
        self.command = command
        self.status = status
    }
}

/// What produced this history row — drives operator copy (banner, chips) without parsing ``source`` strings.
enum RecipeRunHistoryKind: String, Equatable, Sendable, Codable {
    /// Arm-probe / disarm probe from the calibration modal, Mission Control paths, or equivalent.
    case preflightArmProbe
    /// Catalogue **Run** from Vehicle Inspector (`source` still uses `vehicleInspector.recipe.<system>`).
    case vehicleInspectorCatalogueRecipe
    /// In-process automation (e.g. Paladin) or other writers not yet split into a dedicated kind.
    case pluginOther
}

/// One stamped **recipe-run or probe** outcome on a vehicle (newest-first ring buffer on ``FleetVehicleModel/Functions``).
///
/// v1 stores a typed ``RecipeRunHistoryKind`` plus outcome fields in ``SingleVehiclePreflightProbeResult`` (shared
/// "passed / detail / remediation / armedDuringProbe" envelope). A richer ``outcome`` type is deferred until
/// non-probe-shaped runs need distinct fields without lossy mapping.
struct RecipeRunHistoryEntry: Equatable, Identifiable {
    let id: UUID
    let recordedAt: Date
    /// Free-form origin tag (e.g. `"calibrationModal.manual"`, `"vehicleInspector.recipe.core.barometer"`).
    let source: String
    let kind: RecipeRunHistoryKind
    /// v1 physical outcome; see ``RecipeRunHistoryKind`` for semantic interpretation.
    let outcome: SingleVehiclePreflightProbeResult

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        source: String,
        kind: RecipeRunHistoryKind,
        outcome: SingleVehiclePreflightProbeResult
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.source = source
        self.kind = kind
        self.outcome = outcome
    }
}

/// Canonical per-vehicle model: raw data, grouped collections, and domain functions.
struct FleetVehicleModel: Equatable {
    struct DataState: Equatable {
        let vehicleID: String
        /// Stable saturated hex (`#RRGGBB`) for Leaflet / Mission Control markers — assigned when the model is created.
        let mapColorHex: String
        var systemID: Int?
        /// Granular airframe classification — drives ``displayShortID``. Set at SIM spawn time from the preset;
        /// `unknown` for live MAVLink links until MAV_TYPE inference is wired (then surfaces as `VEH:N`).
        var vehicleType: FleetVehicleType
        var telemetry: FleetHubVehicleTelemetry?
        var lastError: String?
    }

    struct Collections: Equatable {
        var lifecycleStatus: VehicleLifecycleStatus
        var telemetrySnapshot: FleetTelemetrySnapshot?
        var operational: FleetVehicleOperationalModel
        var calibration: FleetCalibrationCollection
    }

    struct Functions: Equatable {
        var commandHistory: [FleetVehicleCommandRecord] = []
        var lastCommandError: String?
        /// Commands with `category.arbitrationPriority` below this value are rejected (e.g. manual takeover sets 2 so MC / Paladin at tier 0 are blocked).
        var commandGateMinimumPriority: Int = 0
        /// Recent recipe-run / probe outcomes (newest first, capped to ``recipeRunHistoryCap``).
        ///
        /// Writers: ``FleetLinkService/recordRecipeRun(vehicleID:source:kind:outcome:)`` (arm probes use
        /// ``RecipeRunHistoryKind/preflightArmProbe``). The most recent failed entry is
        /// also overlaid onto ``Collections/calibration`` so a refused arm escalates the matching marker on
        /// the canvas without losing live telemetry-driven updates.
        var recipeRunHistory: [RecipeRunHistoryEntry] = []
    }

    static let recipeRunHistoryCap: Int = 3

    var data: DataState
    var collections: Collections
    var functions: Functions

    /// Per-vehicle map colour: random-looking but **stable** for a given `vehicleID` (same after relaunch).
    static func defaultMapColorHex(forVehicleID vehicleID: String) -> String {
        var gen = MapColorSeededGenerator(seed: fnv1a64(vehicleID.utf8))
        let h = Double.random(in: 0..<360, using: &gen)
        let s = Double.random(in: 0.70...0.92, using: &gen)
        let l = Double.random(in: 0.48...0.60, using: &gen)
        let rgb = hslToRgb(hDegrees: h, s: s, l: l)
        return String(format: "#%02X%02X%02X", rgb.0, rgb.1, rgb.2)
    }

    init(
        vehicleID: String,
        systemID: Int? = nil,
        vehicleType: FleetVehicleType = .unknown,
        initialStatus: VehicleLifecycleStatus = .init(stage: .starting)
    ) {
        let emptyOperational = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: initialStatus)
        let hex = Self.defaultMapColorHex(forVehicleID: vehicleID)
        self.data = DataState(
            vehicleID: vehicleID,
            mapColorHex: hex,
            systemID: systemID,
            vehicleType: vehicleType,
            telemetry: nil,
            lastError: nil
        )
        self.collections = Collections(
            lifecycleStatus: initialStatus,
            telemetrySnapshot: nil,
            operational: emptyOperational,
            calibration: .empty
        )
        self.functions = Functions()
    }

    /// Canonical short identifier shown across logs (`[UAV-C:1]`), vehicle cards, headers, and roster picker rows.
    /// Combines ``FleetVehicleType.classCode`` with the numeric system ID (or vehicleID tail when no sysid is known).
    var displayShortID: String {
        let code = data.vehicleType.classCode
        if let sysid = data.systemID {
            return "\(code):\(sysid)"
        }
        let tail = data.vehicleID.split(separator: ":").last.map(String.init) ?? data.vehicleID
        return "\(code):\(tail)"
    }

    mutating func applyLifecycleStatus(_ status: VehicleLifecycleStatus) {
        collections.lifecycleStatus = status
        collections.operational = FleetVehicleOperationalModel(
            hub: data.telemetry,
            lifecycleStatus: collections.lifecycleStatus
        )
        collections.calibration = FleetCalibrationCollection.make(
            hub: data.telemetry,
            lifecycleStatus: collections.lifecycleStatus,
            vehicleType: data.vehicleType,
            latestRecipeRun: functions.recipeRunHistory.first
        )
    }

    mutating func applyTelemetryMutation(_ mutate: (inout FleetHubVehicleTelemetry) -> Void) {
        var hub = data.telemetry ?? .empty
        mutate(&hub)
        hub.lastUpdate = Date()
        data.telemetry = hub
        collections.telemetrySnapshot = hub.telemetrySnapshot()
        collections.operational = FleetVehicleOperationalModel(
            hub: hub,
            lifecycleStatus: collections.lifecycleStatus
        )
        collections.calibration = FleetCalibrationCollection.make(
            hub: hub,
            lifecycleStatus: collections.lifecycleStatus,
            vehicleType: data.vehicleType,
            latestRecipeRun: functions.recipeRunHistory.first
        )
    }

    /// Records a recipe-run / probe outcome (manual or plugin-driven), keeping the newest first and
    /// capping the buffer at ``recipeRunHistoryCap``. Recomputes ``Collections/calibration`` so the
    /// canvas reflects the new overlay (failed pattern → matching system marker escalates to `.error`).
    mutating func recordRecipeRun(_ entry: RecipeRunHistoryEntry) {
        functions.recipeRunHistory.insert(entry, at: 0)
        if functions.recipeRunHistory.count > Self.recipeRunHistoryCap {
            functions.recipeRunHistory.removeLast(functions.recipeRunHistory.count - Self.recipeRunHistoryCap)
        }
        collections.calibration = FleetCalibrationCollection.make(
            hub: data.telemetry,
            lifecycleStatus: collections.lifecycleStatus,
            vehicleType: data.vehicleType,
            latestRecipeRun: functions.recipeRunHistory.first
        )
    }

    mutating func clearRecipeRuns() {
        functions.recipeRunHistory.removeAll(keepingCapacity: false)
        collections.calibration = FleetCalibrationCollection.make(
            hub: data.telemetry,
            lifecycleStatus: collections.lifecycleStatus,
            vehicleType: data.vehicleType,
            latestRecipeRun: nil
        )
    }

    mutating func applyError(_ message: String?) {
        data.lastError = message
    }

    @discardableResult
    mutating func queueCommand(_ command: FleetVehicleCommand, source: String, category: FleetVehicleCommandCategory) -> UUID {
        let record = FleetVehicleCommandRecord(source: source, category: category, command: command, status: .queued)
        functions.commandHistory.append(record)
        if functions.commandHistory.count > 100 {
            functions.commandHistory.removeFirst(functions.commandHistory.count - 100)
        }
        return record.id
    }

    mutating func markCommandStatus(commandID: UUID, status: FleetVehicleCommandStatus) {
        guard let idx = functions.commandHistory.firstIndex(where: { $0.id == commandID }) else { return }
        functions.commandHistory[idx].status = status
        if case .failed(let message) = status {
            functions.lastCommandError = message
            data.lastError = message
        }
    }
}

// MARK: - Map marker colour (seed-stable “random” hex)

private struct MapColorSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x6A09E667F3BCC909
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func fnv1a64(_ bytes: String.UTF8View) -> UInt64 {
    var h: UInt64 = 14695981039346656037
    for b in bytes {
        h ^= UInt64(b)
        h = h &* 1099511628211
    }
    return h
}

private func hslToRgb(hDegrees: Double, s: Double, l: Double) -> (UInt8, UInt8, UInt8) {
    let h = ((hDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 360.0
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func hue2rgb(_ t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 0.5 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
    let r = hue2rgb(h + 1.0 / 3.0)
    let g = hue2rgb(h)
    let b = hue2rgb(h - 1.0 / 3.0)
    return (
        UInt8(clamping: Int(round(r * 255.0))),
        UInt8(clamping: Int(round(g * 255.0))),
        UInt8(clamping: Int(round(b * 255.0)))
    )
}
