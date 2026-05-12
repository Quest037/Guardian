import Foundation
import SwiftUI

/// Shared, UI-ready vehicle state for cards and badges across the app.
/// This keeps lifecycle + telemetry summaries in one reusable model.
struct FleetVehicleOperationalModel: Equatable {
    let lifecycleStatus: VehicleLifecycleStatus?
    let telemetryAgeS: TimeInterval?
    let battery: BatterySummary
    let gps: GpsSummary
    let movement: MovementSummary

    struct BatterySummary: Equatable {
        let percent0to100: Double?
        let voltageV: Double?
        let currentA: Double?
        let etaSeconds: Double?

        var isCharging: Bool {
            guard let currentA, currentA.isFinite else { return false }
            return currentA < -0.1
        }

        var trendText: String {
            guard let amps = currentA, amps.isFinite else { return "Current —" }
            if amps < -0.1 { return "Charging" }
            if amps > 20 { return "Drain fast" }
            if amps > 5 { return "Draining" }
            if amps > 0.1 { return "Drain slow" }
            return "Stable"
        }

        var etaText: String {
            guard let etaSeconds, etaSeconds.isFinite, etaSeconds > 0 else { return "ETA —" }
            let mins = Int(round(etaSeconds / 60))
            if mins >= 60 {
                let h = mins / 60
                let m = mins % 60
                return String(format: "ETA %dh %02dm", h, m)
            }
            return "ETA \(mins)m"
        }
    }

    struct GpsSummary: Equatable {
        let satellites: Int32?
        let fixShort: String

        var titleText: String {
            let sats = satellites.map { "\($0)" } ?? "—"
            return "GPS \(sats) \(fixShort)"
        }
    }

    struct MovementSummary: Equatable {
        let horizontalSpeedMS: Double?

        /// Speed at or above which the **Moving** triage chip turns green and ``titleText`` leaves “Stationary”.
        /// Kept low so slow ground vehicles (crawl / survey) still read as moving; streams are already **maxed**
        /// across fusion / NED / GPS / odometry so we are not double-counting noise.
        static let operatorMovingSpeedThresholdMS: Double = 0.12

        /// Green **Moving** chip in triage / roster rows.
        var isMovingForOperatorChip: Bool {
            guard let speed = horizontalSpeedMS, speed.isFinite else { return false }
            return speed >= Self.operatorMovingSpeedThresholdMS
        }

        var titleText: String {
            guard let speed = horizontalSpeedMS, speed.isFinite else { return "Motion unknown" }
            if speed < Self.operatorMovingSpeedThresholdMS { return "Stationary" }
            if speed < 3.0 { return String(format: "Moving %.2f", speed) }
            return String(format: "Fast %.1f", speed)
        }
    }
}

// MARK: - Battery traffic (shared with live cards, roster, triage)

/// Traffic-light bucket for battery remaining (icon tint via ``FleetVehicleBatteryTrafficBand/trafficLightIconTint``).
enum FleetVehicleBatteryTrafficBand: Equatable {
    case unknown
    case critical
    case warn
    case ok
}

extension FleetVehicleOperationalModel.BatterySummary {
    /// Aligned with Mission Control roster chips and live run vehicle cards: red below 10%, yellow below 80%, green otherwise.
    var trafficBand: FleetVehicleBatteryTrafficBand {
        guard let p = percent0to100, p.isFinite else { return .unknown }
        if p < 10 { return .critical }
        if p < 80 { return .warn }
        return .ok
    }

    var compactPercentLabel: String {
        guard let p = percent0to100, p.isFinite else { return "—" }
        return "\(Int(round(p)))%"
    }

    /// SF Symbol for compact battery rows (`battery.100` or bolt variant when charging).
    var compactTelemetryBatterySymbolName: String {
        isCharging ? "battery.100.bolt" : "battery.100"
    }

    /// Tooltip / help string for battery hover (percent, V, A, ETA line).
    var compactHoverHelpSummary: String {
        let pct = compactPercentLabel
        let v = voltageV.map { String(format: "%.1f V", $0) } ?? "—"
        let a = currentA.map { String(format: "%.1f A", $0) } ?? "—"
        return "Battery \(pct), \(v), \(a), \(etaText)"
    }
}

extension FleetVehicleOperationalModel {
    init(hub: FleetHubVehicleTelemetry?, lifecycleStatus: VehicleLifecycleStatus?, now: Date = Date()) {
        self.lifecycleStatus = lifecycleStatus
        if let hub {
            telemetryAgeS = max(0, now.timeIntervalSince(hub.lastUpdate))
        } else {
            telemetryAgeS = nil
        }
        battery = Self.makeBatterySummary(hub: hub)
        gps = Self.makeGpsSummary(hub: hub)
        movement = Self.makeMovementSummary(hub: hub)
    }

    private static func makeBatterySummary(hub: FleetHubVehicleTelemetry?) -> BatterySummary {
        let normalizedPercent: Double?
        if let raw = hub?.batteryRemainingPercent, raw.isFinite {
            if raw >= 0, raw <= 1 {
                normalizedPercent = raw * 100
            } else if raw >= 0, raw <= 100 {
                normalizedPercent = raw
            } else {
                normalizedPercent = nil
            }
        } else {
            normalizedPercent = nil
        }
        return BatterySummary(
            percent0to100: normalizedPercent,
            voltageV: hub?.batteryVoltageV,
            currentA: hub?.batteryCurrentA,
            etaSeconds: hub?.batteryTimeRemainingS
        )
    }

    private static func makeGpsSummary(hub: FleetHubVehicleTelemetry?) -> GpsSummary {
        let raw = (hub?.gpsFixType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let u = raw.uppercased()
        let fix: String
        if u.contains("NO_FIX") || u.contains("NO GPS") || raw.isEmpty {
            fix = "—"
        } else if u.contains("FIX_3D") || u.contains("3D_FIX") {
            fix = "3D"
        } else if u.contains("FIX_2D") || u.contains("2D_FIX") {
            fix = "2D"
        } else if u.contains("RTK") {
            fix = "RTK"
        } else if raw.count > 8 {
            fix = String(raw.suffix(6))
        } else {
            fix = raw
        }
        return GpsSummary(satellites: hub?.gpsNumSatellites, fixShort: fix)
    }

    private static func appendPlanarSpeed(north vn: Double?, east ve: Double?, into horizontalCandidates: inout [Double]) {
        switch (vn, ve) {
        case let (a?, b?) where a.isFinite && b.isFinite:
            let h = sqrt(a * a + b * b)
            if h.isFinite { horizontalCandidates.append(h) }
        case let (a?, nil) where a.isFinite:
            horizontalCandidates.append(abs(a))
        case let (nil, b?) where b.isFinite:
            horizontalCandidates.append(abs(b))
        default:
            break
        }
    }

    private static func makeMovementSummary(hub: FleetHubVehicleTelemetry?) -> MovementSummary {
        guard let hub else { return MovementSummary(horizontalSpeedMS: nil) }
        /// MAVSDK can emit **position_velocity_ned** with a fused velocity that stays at 0 while **velocity_ned**
        /// still tracks motion. **Max** across independent streams picks the best signal.
        ///
        /// Slow **UGV** / crawl speeds are included: single-axis NED samples, body-forward odometry when only `vx`
        /// is published, and a 3‑vector odometry norm when all components exist (some stacks use mixed frames).
        var horizontalCandidates: [Double] = []
        appendPlanarSpeed(north: hub.positionVelVnMS, east: hub.positionVelVeMS, into: &horizontalCandidates)
        appendPlanarSpeed(north: hub.velocityNorthMS, east: hub.velocityEastMS, into: &horizontalCandidates)
        if let v = hub.rawGpsVelocityMS, v.isFinite, v >= 0 {
            horizontalCandidates.append(v)
        }
        if let v = hub.fixedWingGroundspeedMS, v.isFinite, v >= 0 {
            horizontalCandidates.append(v)
        }
        let ox = hub.odometryVelXMS
        let oy = hub.odometryVelYMS
        let oz = hub.odometryVelZMS
        if let vx = ox, let vy = oy, let vz = oz, vx.isFinite, vy.isFinite, vz.isFinite {
            let xy = sqrt(vx * vx + vy * vy)
            if xy.isFinite { horizontalCandidates.append(xy) }
            let xyz = sqrt(vx * vx + vy * vy + vz * vz)
            if xyz.isFinite { horizontalCandidates.append(xyz) }
        } else if let vx = ox, let vy = oy, vx.isFinite, vy.isFinite {
            let h = sqrt(vx * vx + vy * vy)
            if h.isFinite { horizontalCandidates.append(h) }
        } else if let vx = ox, let vz = oz, oy == nil, vx.isFinite, vz.isFinite {
            let h = sqrt(vx * vx + vz * vz)
            if h.isFinite { horizontalCandidates.append(h) }
        } else if let vx = ox, oy == nil, oz == nil, vx.isFinite {
            horizontalCandidates.append(abs(vx))
        }
        guard !horizontalCandidates.isEmpty else { return MovementSummary(horizontalSpeedMS: nil) }
        return MovementSummary(horizontalSpeedMS: horizontalCandidates.max())
    }
}

extension FleetVehicleBatteryTrafficBand {
    /// Battery SF Symbol tint (roster, live run cards, assignment triage).
    var trafficLightIconTint: Color {
        switch self {
        case .unknown:
            return Color.gray.opacity(0.55)
        case .critical:
            return Color.red.opacity(0.92)
        case .warn:
            return Color.yellow.opacity(0.95)
        case .ok:
            return GuardianSemanticColors.successForeground
        }
    }
}
