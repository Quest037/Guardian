import Foundation

struct FleetCalibrationSystemID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension FleetCalibrationSystemID {
    static let compass: Self = "core.compass"
    static let accelerometer: Self = "core.accelerometer"
    static let gyrometer: Self = "core.gyrometer"
    static let gps: Self = "core.gps"
    static let localPosition: Self = "core.localPosition"
    static let homePosition: Self = "core.homePosition"
    static let rc: Self = "core.rc"
    static let battery: Self = "core.battery"
    static let barometer: Self = "core.barometer"
    static let ekf: Self = "core.ekf"
}

enum FleetCalibrationStatus: String, Equatable, Codable {
    case green
    case warning
    case error

    var rank: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .green: return 2
        }
    }
}

struct FleetCalibrationSystemDefinition: Equatable, Identifiable {
    let id: FleetCalibrationSystemID
    let title: String
    let iconSystemName: String
    let priority: Int
}

struct FleetCalibrationItem: Equatable, Identifiable {
    let id: FleetCalibrationSystemID
    var status: FleetCalibrationStatus
    var message: String
    var technicalDetail: String?
    var remediationAdvice: PreflightFailureRemediationAdvice?

    init(
        id: FleetCalibrationSystemID,
        status: FleetCalibrationStatus,
        message: String,
        technicalDetail: String? = nil,
        remediationAdvice: PreflightFailureRemediationAdvice? = nil
    ) {
        self.id = id
        self.status = status
        self.message = message
        self.technicalDetail = technicalDetail
        self.remediationAdvice = remediationAdvice
    }
}

struct FleetCalibrationCollection: Equatable {
    var items: [FleetCalibrationItem]

    static let empty = FleetCalibrationCollection(items: [])

    var hasIssues: Bool {
        items.contains { $0.status != .green }
    }

    var worstStatus: FleetCalibrationStatus? {
        items.map(\.status).min { $0.rank < $1.rank }
    }

    func item(for id: FleetCalibrationSystemID) -> FleetCalibrationItem? {
        items.first { $0.id == id }
    }
}

extension FleetCalibrationCollection {
    static func make(
        hub: FleetHubVehicleTelemetry?,
        lifecycleStatus: VehicleLifecycleStatus?,
        vehicleType _: FleetVehicleType,
        latestRecipeRun: RecipeRunHistoryEntry? = nil
    ) -> FleetCalibrationCollection {
        let items: [FleetCalibrationItem] = [
            healthFlagItem(
                id: .compass,
                flag: hub?.healthMagnetometerCalibrationOk,
                failMessage: "Compass calibration is not healthy.",
                failAdvice: .compass
            ),
            healthFlagItem(
                id: .accelerometer,
                flag: hub?.healthAccelerometerCalibrationOk,
                failMessage: "Accelerometer calibration is not healthy.",
                failAdvice: .accelerometer
            ),
            healthFlagItem(
                id: .gyrometer,
                flag: hub?.healthGyrometerCalibrationOk,
                failMessage: "Gyrometer calibration is not healthy.",
                failAdvice: .gyrometer
            ),
            makeGpsItem(hub: hub),
            healthFlagItem(
                id: .localPosition,
                flag: hub?.healthLocalPositionOk,
                failMessage: "Local position estimate is not ready.",
                failAdvice: .localPosition
            ),
            healthFlagItem(
                id: .homePosition,
                flag: hub?.healthHomePositionOk,
                failMessage: "Home position is not ready.",
                failAdvice: .homePosition
            ),
            makeRcItem(hub: hub),
            makeBatteryItem(hub: hub),
            makeBarometerItem(hub: hub),
            makeEkfItem(hub: hub, lifecycleStatus: lifecycleStatus),
        ]

        let overlaid = applyRecipeRunOverlay(items: items, latestRecipeRun: latestRecipeRun)

        return FleetCalibrationCollection(
            items: overlaid.sorted { lhs, rhs in
                FleetCalibrationCoreDefinitions.definition(for: lhs.id).priority
                    < FleetCalibrationCoreDefinitions.definition(for: rhs.id).priority
            }
        )
    }

    /// If the most recent **failed** recipe run carries remediation whose ``patternId`` maps to a known
    /// calibration system, escalate that system's marker to `.error` and replace its remediation advice.
    /// Live telemetry continues to refresh markers on each hub update; operators clear the overlay via
    /// ``FleetLinkService/clearRecipeRuns(vehicleID:)`` / banner dismiss.
    private static func applyRecipeRunOverlay(
        items: [FleetCalibrationItem],
        latestRecipeRun: RecipeRunHistoryEntry?
    ) -> [FleetCalibrationItem] {
        guard
            let entry = latestRecipeRun,
            entry.outcome.passed == false,
            let advice = entry.outcome.remediationAdvice,
            let targetID = preflightSystemID(forPatternID: advice.patternId)
        else {
            return items
        }

        var mutated = items
        if let idx = mutated.firstIndex(where: { $0.id == targetID }) {
            let original = mutated[idx]
            mutated[idx] = FleetCalibrationItem(
                id: original.id,
                status: .error,
                message: advice.summary,
                technicalDetail: entry.outcome.detail,
                remediationAdvice: advice
            )
        }
        return mutated
    }

    /// Maps a `PreflightFailureRemediationAdvice.patternId` to the calibration system it should colour.
    /// Patterns without a per-system home (e.g. `common.geofence`, `generic.arm_denied`) return `nil`
    /// — the banner still surfaces them, but no marker is repainted.
    private static func preflightSystemID(forPatternID patternId: String) -> FleetCalibrationSystemID? {
        if patternId.hasPrefix(VehicleInspectorRecipeRunHistoryMapper.wizardCalibrationFailurePatternPrefix) {
            let raw = String(patternId.dropFirst(VehicleInspectorRecipeRunHistoryMapper.wizardCalibrationFailurePatternPrefix.count))
            return FleetCalibrationSystemID(rawValue: raw)
        }
        switch patternId {
        case "common.compass_mag", "px4.heading_estimate_invalid":
            return .compass
        case "ardupilot.accels_inconsistent":
            return .accelerometer
        case "common.gps_position":
            return .gps
        case "common.rc":
            return .rc
        case "common.ekf":
            return .ekf
        default:
            return nil
        }
    }

    private static func healthFlagItem(
        id: FleetCalibrationSystemID,
        flag: Bool?,
        failMessage: String,
        failAdvice: PreflightFailureRemediationAdvice
    ) -> FleetCalibrationItem {
        switch flag {
        case .some(true):
            return FleetCalibrationItem(id: id, status: .green, message: "System is a go!")
        case .some(false):
            return FleetCalibrationItem(id: id, status: .error, message: failMessage, remediationAdvice: failAdvice)
        case .none:
            return awaitingItem(id: id)
        }
    }

    private static func makeGpsItem(hub: FleetHubVehicleTelemetry?) -> FleetCalibrationItem {
        guard let hub,
              hub.healthGlobalPositionOk != nil || hub.gpsNumSatellites != nil || hub.gpsFixType != nil
        else {
            return awaitingItem(id: .gps)
        }

        if hub.healthGlobalPositionOk == true {
            return FleetCalibrationItem(id: .gps, status: .green, message: "System is a go!", technicalDetail: gpsDetail(hub: hub))
        }
        if hub.healthGlobalPositionOk == false {
            return FleetCalibrationItem(
                id: .gps,
                status: .error,
                message: "GPS/global position is not ready.",
                technicalDetail: gpsDetail(hub: hub),
                remediationAdvice: .gps
            )
        }

        let satellites = hub.gpsNumSatellites ?? 0
        let fix = (hub.gpsFixType ?? "").uppercased()
        if fix.contains("NO_FIX") || satellites < 4 {
            return FleetCalibrationItem(
                id: .gps,
                status: .error,
                message: "GPS has no reliable fix.",
                technicalDetail: gpsDetail(hub: hub),
                remediationAdvice: .gps
            )
        }
        if satellites < 6 {
            return FleetCalibrationItem(
                id: .gps,
                status: .warning,
                message: "GPS fix is present but weak.",
                technicalDetail: gpsDetail(hub: hub),
                remediationAdvice: .gps
            )
        }
        return FleetCalibrationItem(id: .gps, status: .green, message: "System is a go!", technicalDetail: gpsDetail(hub: hub))
    }

    private static func makeRcItem(hub: FleetHubVehicleTelemetry?) -> FleetCalibrationItem {
        guard let hub, hub.rcIsAvailable != nil || hub.rcSignalStrengthPercent != nil else {
            return awaitingItem(id: .rc)
        }
        if hub.rcIsAvailable == false {
            return FleetCalibrationItem(id: .rc, status: .error, message: "RC link is not available.", remediationAdvice: .rc)
        }
        if let strength = hub.rcSignalStrengthPercent, strength.isFinite, strength < 35 {
            return FleetCalibrationItem(
                id: .rc,
                status: .warning,
                message: "RC signal is weak.",
                technicalDetail: String(format: "Signal %.0f%%", strength),
                remediationAdvice: .rc
            )
        }
        return FleetCalibrationItem(id: .rc, status: .green, message: "System is a go!")
    }

    private static func makeBatteryItem(hub: FleetHubVehicleTelemetry?) -> FleetCalibrationItem {
        guard let raw = hub?.batteryRemainingPercent, raw.isFinite else {
            return awaitingItem(id: .battery)
        }
        let percent = raw <= 1 ? raw * 100 : raw
        if percent < 15 {
            return FleetCalibrationItem(
                id: .battery,
                status: .error,
                message: "Battery level is critical.",
                technicalDetail: String(format: "%.0f%% remaining", percent),
                remediationAdvice: .battery
            )
        }
        if percent < 25 {
            return FleetCalibrationItem(
                id: .battery,
                status: .warning,
                message: "Battery level is low.",
                technicalDetail: String(format: "%.0f%% remaining", percent),
                remediationAdvice: .battery
            )
        }
        return FleetCalibrationItem(
            id: .battery,
            status: .green,
            message: "System is a go!",
            technicalDetail: String(format: "%.0f%% remaining", percent)
        )
    }

    private static func makeBarometerItem(hub: FleetHubVehicleTelemetry?) -> FleetCalibrationItem {
        guard let hub, hub.scaledPressureAbsoluteHpa != nil || hub.scaledPressureDifferentialHpa != nil else {
            return awaitingItem(id: .barometer)
        }
        return FleetCalibrationItem(id: .barometer, status: .green, message: "System is a go!")
    }

    private static func makeEkfItem(
        hub: FleetHubVehicleTelemetry?,
        lifecycleStatus: VehicleLifecycleStatus?
    ) -> FleetCalibrationItem {
        guard let healthAllOk = hub?.healthAllOk else {
            return awaitingItem(id: .ekf)
        }
        return FleetCalibrationItem(
            id: .ekf,
            status: healthAllOk ? .green : .error,
            message: healthAllOk ? "System is a go!" : "Autopilot health checks are not all clear.",
            technicalDetail: lifecycleStatus?.sentence,
            remediationAdvice: healthAllOk ? nil : .ekf
        )
    }

    /// Default `.warning` placeholder when the underlying telemetry has not arrived yet.
    /// Keeps every core system visible on the image so operators can see the full readiness
    /// landscape (real-state items overwrite this once health/sensor events land).
    private static func awaitingItem(id: FleetCalibrationSystemID) -> FleetCalibrationItem {
        FleetCalibrationItem(
            id: id,
            status: .warning,
            message: "Awaiting telemetry…"
        )
    }

    private static func gpsDetail(hub: FleetHubVehicleTelemetry) -> String {
        let sats = hub.gpsNumSatellites.map { "\($0) sats" } ?? "satellites unknown"
        let fix = hub.gpsFixType ?? "fix unknown"
        return "\(sats), \(fix)"
    }
}

enum FleetCalibrationCoreDefinitions {
    static let definitions: [FleetCalibrationSystemDefinition] = [
        .init(id: .compass, title: "Compass", iconSystemName: "safari", priority: 10),
        .init(id: .accelerometer, title: "Accelerometer", iconSystemName: "gyroscope", priority: 20),
        .init(id: .gyrometer, title: "Gyrometer", iconSystemName: "rotate.3d", priority: 30),
        .init(id: .gps, title: "GPS", iconSystemName: "location", priority: 40),
        .init(id: .localPosition, title: "Local position", iconSystemName: "point.3.connected.trianglepath.dotted", priority: 50),
        .init(id: .homePosition, title: "Home position", iconSystemName: "house", priority: 60),
        .init(id: .rc, title: "RC link", iconSystemName: "antenna.radiowaves.left.and.right", priority: 70),
        .init(id: .battery, title: "Battery", iconSystemName: "battery.75percent", priority: 80),
        .init(id: .barometer, title: "Barometer", iconSystemName: "barometer", priority: 90),
        .init(id: .ekf, title: "Estimator", iconSystemName: "waveform.path.ecg", priority: 100),
    ]

    static func definition(for id: FleetCalibrationSystemID) -> FleetCalibrationSystemDefinition {
        definitions.first { $0.id == id }
            ?? FleetCalibrationSystemDefinition(id: id, title: id.rawValue, iconSystemName: "dot.radiowaves.left.and.right", priority: 1_000)
    }
}

private extension PreflightFailureRemediationAdvice {
    static let compass = PreflightFailureRemediationAdvice(
        patternId: "calibration.compass",
        summary: "Compass / magnetometer needs attention.",
        steps: [
            "Move away from metal, speakers, batteries, and high-current wiring.",
            "Run the compass calibration procedure for the active autopilot stack.",
            "Retry outdoors or in an environment with low magnetic interference.",
        ]
    )

    static let accelerometer = PreflightFailureRemediationAdvice(
        patternId: "calibration.accelerometer",
        summary: "Accelerometer calibration is not healthy.",
        steps: [
            "Place the vehicle level and keep it still while the IMU settles.",
            "Run accelerometer calibration if the airframe or controller mounting changed.",
            "Power-cycle and wait for estimator readiness before retrying.",
        ]
    )

    static let gyrometer = PreflightFailureRemediationAdvice(
        patternId: "calibration.gyrometer",
        summary: "Gyrometer calibration is not healthy.",
        steps: [
            "Keep the vehicle completely still during boot and calibration.",
            "Check for vibration, loose flight-controller mounting, or a warm-up period.",
            "Run gyro/IMU calibration in the stack tools, then retry.",
        ]
    )

    static let gps = PreflightFailureRemediationAdvice(
        patternId: "calibration.gps",
        summary: "GPS or global position is not ready.",
        steps: [
            "Wait for a solid GPS fix with enough satellites and acceptable HDOP.",
            "Move outdoors with a clear sky view and check antenna placement.",
            "Confirm GPS is enabled and reporting through telemetry.",
        ]
    )

    static let localPosition = PreflightFailureRemediationAdvice(
        patternId: "calibration.local_position",
        summary: "Local position estimate is not ready.",
        steps: [
            "Allow the estimator to initialize after boot.",
            "Keep the vehicle still and verify IMU/GPS health before arming.",
            "Check autopilot status text for the specific local-position blocker.",
        ]
    )

    static let homePosition = PreflightFailureRemediationAdvice(
        patternId: "calibration.home_position",
        summary: "Home position has not been established.",
        steps: [
            "Wait for GPS/global position and home position to initialize.",
            "Verify the vehicle has a valid launch/home origin before mission use.",
            "Retry after the autopilot reports home position ready.",
        ]
    )

    static let rc = PreflightFailureRemediationAdvice(
        patternId: "calibration.rc",
        summary: "RC / radio link needs attention.",
        steps: [
            "Turn on and bind the handset, then verify the autopilot sees RC input.",
            "Check receiver power, antenna orientation, and radio failsafe settings.",
            "For simulation, enable or map the virtual RC source required by the stack.",
        ]
    )

    static let battery = PreflightFailureRemediationAdvice(
        patternId: "calibration.battery",
        summary: "Battery state is not mission-ready.",
        steps: [
            "Charge or replace the battery before calibration or mission work.",
            "Verify voltage, current sensor, and remaining-capacity telemetry are sane.",
            "Do not start calibration routines that require motors while battery is critical.",
        ]
    )

    static let ekf = PreflightFailureRemediationAdvice(
        patternId: "calibration.ekf",
        summary: "Estimator / autopilot health checks are not all clear.",
        steps: [
            "Wait for the estimator to align and avoid moving the vehicle during initialization.",
            "Check GPS, compass, accelerometer, and gyro readiness first.",
            "Review recent autopilot status text for the failing health check.",
        ]
    )
}
