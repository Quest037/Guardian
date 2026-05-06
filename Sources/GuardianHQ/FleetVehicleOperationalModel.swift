import Foundation

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

        var titleText: String {
            guard let speed = horizontalSpeedMS, speed.isFinite else { return "Motion unknown" }
            if speed < 0.5 { return "Stationary" }
            if speed < 3.0 { return String(format: "Moving %.1f", speed) }
            return String(format: "Fast %.1f", speed)
        }
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

    private static func makeMovementSummary(hub: FleetHubVehicleTelemetry?) -> MovementSummary {
        if let vn = hub?.positionVelVnMS, let ve = hub?.positionVelVeMS, vn.isFinite, ve.isFinite {
            return MovementSummary(horizontalSpeedMS: sqrt((vn * vn) + (ve * ve)))
        }
        if let vn = hub?.velocityNorthMS, let ve = hub?.velocityEastMS, vn.isFinite, ve.isFinite {
            return MovementSummary(horizontalSpeedMS: sqrt((vn * vn) + (ve * ve)))
        }
        if let v = hub?.rawGpsVelocityMS, v.isFinite {
            return MovementSummary(horizontalSpeedMS: v)
        }
        return MovementSummary(horizontalSpeedMS: nil)
    }
}
