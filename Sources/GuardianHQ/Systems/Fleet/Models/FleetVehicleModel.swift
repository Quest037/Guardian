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
    /// Upload items to the autopilot, arm, then start mission execution (MAVSDK Mission plugin).
    case uploadAndStartMission(items: [Mavsdk.Mission.MissionItem])
    /// Command the autopilot to return to launch / home (MAVSDK Action plugin).
    case returnToLaunch
    /// Command the autopilot to land now (where supported).
    case land
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
    }

    struct Functions: Equatable {
        var commandHistory: [FleetVehicleCommandRecord] = []
        var lastCommandError: String?
        /// Commands with `category.arbitrationPriority` below this value are rejected (e.g. manual takeover sets 2 so MC / Paladin at tier 0 are blocked).
        var commandGateMinimumPriority: Int = 0
    }

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
            operational: emptyOperational
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
