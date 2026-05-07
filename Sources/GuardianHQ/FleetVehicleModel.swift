import Foundation
import Mavsdk

/// Who is allowed to preempt lower-priority command streams (keyboard takeover, free roam, Paladin).
enum FleetVehicleCommandCategory: String, Equatable, Comparable {
    case paladin
    case freeRoamKeyboard
    case manualTakeover

    /// Higher rejects lower when `commandGateMinimumPriority` is raised.
    var arbitrationPriority: Int {
        switch self {
        case .paladin: return 0
        case .freeRoamKeyboard: return 1
        case .manualTakeover: return 2
        }
    }

    static func < (lhs: FleetVehicleCommandCategory, rhs: FleetVehicleCommandCategory) -> Bool {
        lhs.arbitrationPriority < rhs.arbitrationPriority
    }
}

enum FleetVehicleCommand: Equatable {
    case arm
    case disarm
    case gotoCoordinate(RouteCoordinate, relativeAltitudeM: Double, yawDeg: Double)
    /// Upload items to the autopilot, arm, then start mission execution (MAVSDK Mission plugin).
    case uploadAndStartMission(items: [Mavsdk.Mission.MissionItem])
    /// Command the autopilot to return to launch / home (MAVSDK Action plugin).
    case returnToLaunch
}

enum FleetVehicleCommandStatus: Equatable {
    case queued
    case sent
    case succeeded
    case failed(String)
}

/// MAVSDK Completable result surfaced to Mission Control / Paladin (upload, arm, goto, etc.).
enum PaladinFleetCommandAsyncOutcome: Equatable {
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
        category: FleetVehicleCommandCategory = .paladin,
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
        /// Commands with `category.arbitrationPriority` below this value are rejected (e.g. manual takeover sets 2 so Paladin at 0 is blocked).
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

    init(vehicleID: String, systemID: Int? = nil, initialStatus: VehicleLifecycleStatus = .init(stage: .starting)) {
        let emptyOperational = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: initialStatus)
        let hex = Self.defaultMapColorHex(forVehicleID: vehicleID)
        self.data = DataState(vehicleID: vehicleID, mapColorHex: hex, systemID: systemID, telemetry: nil, lastError: nil)
        self.collections = Collections(
            lifecycleStatus: initialStatus,
            telemetrySnapshot: nil,
            operational: emptyOperational
        )
        self.functions = Functions()
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
