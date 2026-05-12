import Foundation

/// Live triage-style chips (arm / motion / mode / battery / altitude) derived from hub telemetry and ``FleetVehicleOperationalModel``.
/// UI maps ``Chip/isActive`` to success (green) vs neutral (gray):
/// - **Armed** chip title is always `Armed`; green only when the vehicle is armed (grey when disarmed or unknown).
/// - **Moving** chip title is always `Moving`; green when the fused speed estimate is at or above
///   ``FleetVehicleOperationalModel/MovementSummary/operatorMovingSpeedThresholdMS`` (~0.12 m/s so slow UGV crawl counts).
/// - **Mode** chip title is the humanized mode; green for every mode except hold-like modes (grey for hold).
/// - **Battery** chip uses traffic-light icon tint from ``FleetVehicleBatteryTrafficBand`` (see roster / live run cards).
/// - **AGL** uses bridge ``FleetHubVehicleTelemetry/relativeAltM`` (MAVLink relative / home-relative height — treated as operator AGL-style readout when terrain is not modeled separately).
struct FleetVehicleLiveStatusBadgeRow: Equatable {
    struct Chip: Equatable {
        var title: String
        /// When `true`, surfaces use success (green) styling; when `false`, neutral (gray).
        var isActive: Bool
    }

    /// Compact battery capsule: percent label, symbol name, and traffic band for icon tint.
    struct BatteryChip: Equatable {
        var percentLabel: String
        var systemImageName: String
        var trafficBand: FleetVehicleBatteryTrafficBand
        var helpSummary: String
    }

    /// Relative height for triage (label + tooltip); see ``compactAGLTitle(from:)``.
    struct AltitudeChip: Equatable {
        var title: String
        var helpSummary: String
    }

    var arm: Chip
    /// Label is always “Moving”; ``Chip/isActive`` uses ``FleetVehicleOperationalModel/MovementSummary/isMovingForOperatorChip``.
    var motion: Chip
    var mode: Chip
    var battery: BatteryChip
    var altitude: AltitudeChip

    init(hub: FleetHubVehicleTelemetry?, operational: FleetVehicleOperationalModel) {
        let armed = hub?.isArmed == true
        self.arm = Chip(title: "Armed", isActive: armed)

        let moving = operational.movement.isMovingForOperatorChip
        self.motion = Chip(title: "Moving", isActive: moving)

        let modeTitle = Self.humanizedFlightMode(from: hub)
        let modeActive = !Self.isHoldLikeFlightMode(humanized: modeTitle, rawFlightMode: hub?.flightMode ?? "")
        self.mode = Chip(title: modeTitle, isActive: modeActive)

        let b = operational.battery
        self.battery = BatteryChip(
            percentLabel: b.compactPercentLabel,
            systemImageName: b.compactTelemetryBatterySymbolName,
            trafficBand: b.trafficBand,
            helpSummary: b.compactHoverHelpSummary
        )
        self.altitude = AltitudeChip(
            title: Self.compactAGLTitle(from: hub),
            helpSummary: Self.aglHelpSummary(from: hub)
        )
    }
}

extension FleetVehicleModel {
    /// Live arm / motion / mode chips for roster cards, triage rows, and other operator glances.
    var liveStatusBadgeRow: FleetVehicleLiveStatusBadgeRow {
        FleetVehicleLiveStatusBadgeRow(hub: data.telemetry, operational: collections.operational)
    }
}

extension FleetVehicleLiveStatusBadgeRow {
    /// Human-readable flight mode for chips (enum suffix after `.`, underscores → spaces).
    static func humanizedFlightMode(from hub: FleetHubVehicleTelemetry?) -> String {
        guard let hub else { return "Mode —" }
        let raw = hub.flightMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "—" { return "Mode —" }
        if let dot = raw.lastIndex(of: ".") {
            let suffix = String(raw[raw.index(after: dot)...])
            return suffix.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
        return raw.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    /// Short operator label for AGL-style height (`AGL 42m` or `AGL —`). Uses ``FleetHubVehicleTelemetry/relativeAltM``.
    static func compactAGLTitle(from hub: FleetHubVehicleTelemetry?) -> String {
        guard let m = hub?.relativeAltM, m.isFinite else { return "AGL —" }
        return "AGL \(Int(round(m)))m"
    }

    /// Tooltip for the AGL chip (bridge semantics).
    static func aglHelpSummary(from hub: FleetHubVehicleTelemetry?) -> String {
        guard let m = hub?.relativeAltM, m.isFinite else {
            return "Relative height from bridge not available. AGL uses vehicle relative altitude when the bridge reports it."
        }
        return "Relative altitude (AGL-style): \(Int(round(m))) m — from bridge relative height (typically above home / launch reference)."
    }

    /// Hold-like modes use neutral (gray) styling; all other titles (including `Mode —`) use active (green) styling.
    static func isHoldLikeFlightMode(humanized: String, rawFlightMode: String) -> Bool {
        let h = humanized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h == "hold" { return true }
        let raw = rawFlightMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = raw.uppercased()
        if u.contains(".HOLD") || u.contains("_HOLD") || u == "HOLD" { return true }
        if u.contains("HOLD_") { return true }
        return false
    }
}
