import Foundation

/// Curated catalogue of ``FleetHubVehicleTelemetry`` fields for the Vehicle Inspector.
///
/// Drives two surfaces:
/// 1. **Calibration tab** — `fields(forSystem:)` returns the ordered set of catalog entries that
///    should appear in the right column of the per-system status block when an operator selects
///    a calibration marker (Compass → heading + mag, Battery → V/A/%, etc).
/// 2. **Telemetry tab** — `allFields()` and `groups` drive the chip strip and grouped list.
///    Anything in `FleetHubVehicleTelemetry` that is **not** present in the catalog is surfaced
///    under the synthetic ``Group/other`` chip via `unknownFields(in:)` so the Mirror-dump
///    completeness benefit of the old raw view is preserved without exploding the curated UI.
///
/// **Catalogue is v1.** Per `TODO.md` it needs a content pass to tighten labels, formatters, and
/// per-system mappings. Adding a new field to ``FleetHubVehicleTelemetry`` does **not** require
/// a catalog change for the app to keep compiling — uncatalogued fields gracefully appear under
/// "Other".
enum FleetTelemetryFieldCatalog {
    /// Group chips shown in the Telemetry tab. ``flight``/``identity`` come first to match the
    /// existing telemetry sheet groupings; physical-sensor groups follow.
    enum Group: String, CaseIterable, Identifiable, Hashable, Sendable {
        case identity
        case flight
        case health
        case battery
        case position
        case home
        case attitude
        case motion
        case altitude
        case gps
        case rawGps
        case rc
        case imu
        case pressure
        case wind
        case distance
        case fixedWingVTOL
        case odometry
        case mission
        case status
        case time
        case other

        var id: String { rawValue }

        /// Display label shown on the chip and as the section header in the grouped list.
        var displayLabel: String {
            switch self {
            case .identity: return "Identity"
            case .flight: return "Flight"
            case .health: return "Health"
            case .battery: return "Battery"
            case .position: return "Position"
            case .home: return "Home"
            case .attitude: return "Attitude"
            case .motion: return "Motion"
            case .altitude: return "Altitude"
            case .gps: return "GPS"
            case .rawGps: return "GPS (raw)"
            case .rc: return "RC"
            case .imu: return "IMU"
            case .pressure: return "Pressure"
            case .wind: return "Wind"
            case .distance: return "Distance"
            case .fixedWingVTOL: return "Fixed-wing / VTOL"
            case .odometry: return "Odometry"
            case .mission: return "Mission"
            case .status: return "Status"
            case .time: return "Time"
            case .other: return "Other"
            }
        }

        /// SF Symbol used on the chip.
        var iconSystemName: String {
            switch self {
            case .identity: return "info.circle"
            case .flight: return "airplane.circle"
            case .health: return "heart.text.square"
            case .battery: return "battery.75percent"
            case .position: return "location"
            case .home: return "house"
            case .attitude: return "rotate.3d"
            case .motion: return "speedometer"
            case .altitude: return "arrow.up.and.down"
            case .gps: return "location.viewfinder"
            case .rawGps: return "antenna.radiowaves.left.and.right"
            case .rc: return "av.remote"
            case .imu: return "gyroscope"
            case .pressure: return "barometer"
            case .wind: return "wind"
            case .distance: return "ruler"
            case .fixedWingVTOL: return "paperplane"
            case .odometry: return "point.3.connected.trianglepath.dotted"
            case .mission: return "list.bullet.rectangle"
            case .status: return "text.bubble"
            case .time: return "clock"
            case .other: return "ellipsis.circle"
            }
        }
    }

    /// One catalogued telemetry field — its identifier (the property name on
    /// ``FleetHubVehicleTelemetry`` for stable matching), display label, group and a
    /// `(hub) -> String?` formatter that returns the rendered value or `nil` if absent.
    struct Field: Identifiable, Equatable, Sendable {
        let id: String
        let displayLabel: String
        let group: Group
        let format: @Sendable (FleetHubVehicleTelemetry) -> String?

        static func == (lhs: Field, rhs: Field) -> Bool { lhs.id == rhs.id }
    }

    /// Display order across the whole catalogue. The Telemetry tab honours this order within each
    /// group; the per-system view uses the order returned by ``fields(forSystem:)``.
    static let all: [Field] = [
        // MARK: Identity
        .init(id: "autopilotStack", displayLabel: "Autopilot", group: .identity) { hub in
            hub.autopilotStack == .unknown ? nil : hub.autopilotStack.displayName
        },
        .init(id: "flightSwVersion", displayLabel: "FW version", group: .identity) { hub in
            guard let mj = hub.flightSwMajor, let mn = hub.flightSwMinor, let pt = hub.flightSwPatch else { return nil }
            return "\(mj).\(mn).\(pt)"
        },
        .init(id: "flightSwGitHash", displayLabel: "FW git", group: .identity) { hub in hub.flightSwGitHash },
        .init(id: "osSwGitHash", displayLabel: "OS git", group: .identity) { hub in hub.osSwGitHash },
        .init(id: "flightSwVersionType", displayLabel: "FW build", group: .identity) { hub in hub.flightSwVersionType },

        // MARK: Flight
        .init(id: "isArmed", displayLabel: "Armed", group: .flight) { hub in hub.isArmed ? "Yes" : "No" },
        .init(id: "flightMode", displayLabel: "Mode", group: .flight) { hub in
            hub.flightMode.trimmingCharacters(in: .whitespaces).isEmpty ? nil : hub.flightMode
        },
        .init(id: "inAir", displayLabel: "In air", group: .flight) { hub in hub.inAir.map { $0 ? "Yes" : "No" } },
        .init(id: "landedState", displayLabel: "Landed state", group: .flight) { hub in hub.landedState },
        .init(id: "missionProgress", displayLabel: "Mission progress", group: .mission) { hub in
            guard let cur = hub.missionProgressCurrent, let tot = hub.missionProgressTotal else { return nil }
            return "\(cur) / \(tot)"
        },

        // MARK: Health
        .init(id: "healthAllOk", displayLabel: "Health all OK", group: .health) { hub in hub.healthAllOk.map(yesNo) },
        .init(id: "healthArmable", displayLabel: "Armable", group: .health) { hub in hub.healthArmable.map(yesNo) },
        .init(id: "healthGyrometerCalibrationOk", displayLabel: "Gyrometer cal", group: .health) { hub in hub.healthGyrometerCalibrationOk.map(yesNo) },
        .init(id: "healthAccelerometerCalibrationOk", displayLabel: "Accelerometer cal", group: .health) { hub in hub.healthAccelerometerCalibrationOk.map(yesNo) },
        .init(id: "healthMagnetometerCalibrationOk", displayLabel: "Magnetometer cal", group: .health) { hub in hub.healthMagnetometerCalibrationOk.map(yesNo) },
        .init(id: "healthLocalPositionOk", displayLabel: "Local position", group: .health) { hub in hub.healthLocalPositionOk.map(yesNo) },
        .init(id: "healthGlobalPositionOk", displayLabel: "Global position", group: .health) { hub in hub.healthGlobalPositionOk.map(yesNo) },
        .init(id: "healthHomePositionOk", displayLabel: "Home position", group: .health) { hub in hub.healthHomePositionOk.map(yesNo) },

        // MARK: Battery
        .init(id: "batteryRemainingPercent", displayLabel: "Remaining", group: .battery) { hub in formatPercent(hub.batteryRemainingPercent) },
        .init(id: "batteryVoltageV", displayLabel: "Voltage", group: .battery) { hub in formatUnit(hub.batteryVoltageV, "V", digits: 1) },
        .init(id: "batteryCurrentA", displayLabel: "Current", group: .battery) { hub in formatUnit(hub.batteryCurrentA, "A", digits: 1) },
        .init(id: "batteryCapacityConsumedAh", displayLabel: "Consumed", group: .battery) { hub in formatUnit(hub.batteryCapacityConsumedAh, "Ah", digits: 2) },
        .init(id: "batteryTimeRemainingS", displayLabel: "Time left", group: .battery) { hub in formatSecondsAsDuration(hub.batteryTimeRemainingS) },
        .init(id: "batteryTempDegC", displayLabel: "Temp", group: .battery) { hub in formatUnit(hub.batteryTempDegC, "°C", digits: 1) },
        .init(id: "batteryId", displayLabel: "ID", group: .battery) { hub in hub.batteryId.map(String.init) },

        // MARK: Position
        .init(id: "latitudeDeg", displayLabel: "Latitude", group: .position) { hub in formatDeg(hub.latitudeDeg, digits: 5) },
        .init(id: "longitudeDeg", displayLabel: "Longitude", group: .position) { hub in formatDeg(hub.longitudeDeg, digits: 5) },
        .init(id: "absoluteAltM", displayLabel: "Abs altitude", group: .position) { hub in formatUnit(hub.absoluteAltM, "m", digits: 1) },
        .init(id: "relativeAltM", displayLabel: "Rel altitude", group: .position) { hub in formatUnit(hub.relativeAltM, "m", digits: 1) },

        // MARK: Home
        .init(id: "homeLatitudeDeg", displayLabel: "Home lat", group: .home) { hub in formatDeg(hub.homeLatitudeDeg, digits: 5) },
        .init(id: "homeLongitudeDeg", displayLabel: "Home lon", group: .home) { hub in formatDeg(hub.homeLongitudeDeg, digits: 5) },
        .init(id: "homeAbsoluteAltM", displayLabel: "Home abs alt", group: .home) { hub in formatUnit(hub.homeAbsoluteAltM, "m", digits: 1) },
        .init(id: "homeRelativeAltM", displayLabel: "Home rel alt", group: .home) { hub in formatUnit(hub.homeRelativeAltM, "m", digits: 1) },

        // MARK: Attitude
        .init(id: "rollDeg", displayLabel: "Roll", group: .attitude) { hub in formatUnit(hub.rollDeg, "°", digits: 1) },
        .init(id: "pitchDeg", displayLabel: "Pitch", group: .attitude) { hub in formatUnit(hub.pitchDeg, "°", digits: 1) },
        .init(id: "yawDeg", displayLabel: "Yaw", group: .attitude) { hub in formatUnit(hub.yawDeg, "°", digits: 1) },
        .init(id: "headingDeg", displayLabel: "Heading", group: .attitude) { hub in formatUnit(hub.headingDeg, "°", digits: 1) },
        .init(id: "angularVelRollRadS", displayLabel: "Roll rate", group: .attitude) { hub in formatUnit(hub.angularVelRollRadS, "rad/s", digits: 2) },
        .init(id: "angularVelPitchRadS", displayLabel: "Pitch rate", group: .attitude) { hub in formatUnit(hub.angularVelPitchRadS, "rad/s", digits: 2) },
        .init(id: "angularVelYawRadS", displayLabel: "Yaw rate", group: .attitude) { hub in formatUnit(hub.angularVelYawRadS, "rad/s", digits: 2) },

        // MARK: Motion (NED velocities)
        .init(id: "velocityNorthMS", displayLabel: "Velocity N", group: .motion) { hub in formatUnit(hub.velocityNorthMS, "m/s", digits: 2) },
        .init(id: "velocityEastMS", displayLabel: "Velocity E", group: .motion) { hub in formatUnit(hub.velocityEastMS, "m/s", digits: 2) },
        .init(id: "velocityDownMS", displayLabel: "Velocity D", group: .motion) { hub in formatUnit(hub.velocityDownMS, "m/s", digits: 2) },
        .init(id: "positionVelHeadingDeg", displayLabel: "Track heading", group: .motion) { hub in formatUnit(hub.positionVelHeadingDeg, "°", digits: 1) },

        // MARK: Altitude
        .init(id: "altitudeAmslM", displayLabel: "AMSL", group: .altitude) { hub in formatUnit(hub.altitudeAmslM, "m", digits: 1) },
        .init(id: "altitudeMonotonicM", displayLabel: "Monotonic", group: .altitude) { hub in formatUnit(hub.altitudeMonotonicM, "m", digits: 1) },
        .init(id: "altitudeLocalM", displayLabel: "Local", group: .altitude) { hub in formatUnit(hub.altitudeLocalM, "m", digits: 1) },
        .init(id: "altitudeRelativeM", displayLabel: "Relative", group: .altitude) { hub in formatUnit(hub.altitudeRelativeM, "m", digits: 1) },
        .init(id: "altitudeTerrainM", displayLabel: "Terrain", group: .altitude) { hub in formatUnit(hub.altitudeTerrainM, "m", digits: 1) },
        .init(id: "altitudeBottomClearanceM", displayLabel: "Bottom clearance", group: .altitude) { hub in formatUnit(hub.altitudeBottomClearanceM, "m", digits: 2) },

        // MARK: GPS (decoded)
        .init(id: "gpsNumSatellites", displayLabel: "Satellites", group: .gps) { hub in hub.gpsNumSatellites.map { String($0) } },
        .init(id: "gpsFixType", displayLabel: "Fix type", group: .gps) { hub in hub.gpsFixType },

        // MARK: GPS (raw)
        .init(id: "rawGpsLatitudeDeg", displayLabel: "Raw lat", group: .rawGps) { hub in formatDeg(hub.rawGpsLatitudeDeg, digits: 5) },
        .init(id: "rawGpsLongitudeDeg", displayLabel: "Raw lon", group: .rawGps) { hub in formatDeg(hub.rawGpsLongitudeDeg, digits: 5) },
        .init(id: "rawGpsAbsoluteAltM", displayLabel: "Raw abs alt", group: .rawGps) { hub in formatUnit(hub.rawGpsAbsoluteAltM, "m", digits: 1) },
        .init(id: "rawGpsAltitudeEllipsoidM", displayLabel: "Ellipsoid alt", group: .rawGps) { hub in formatUnit(hub.rawGpsAltitudeEllipsoidM, "m", digits: 1) },
        .init(id: "rawGpsHdop", displayLabel: "HDOP", group: .rawGps) { hub in formatUnit(hub.rawGpsHdop, "", digits: 2) },
        .init(id: "rawGpsVdop", displayLabel: "VDOP", group: .rawGps) { hub in formatUnit(hub.rawGpsVdop, "", digits: 2) },
        .init(id: "rawGpsVelocityMS", displayLabel: "Raw velocity", group: .rawGps) { hub in formatUnit(hub.rawGpsVelocityMS, "m/s", digits: 2) },
        .init(id: "rawGpsCogDeg", displayLabel: "COG", group: .rawGps) { hub in formatUnit(hub.rawGpsCogDeg, "°", digits: 1) },
        .init(id: "rawGpsHorizUncertaintyM", displayLabel: "Horiz σ", group: .rawGps) { hub in formatUnit(hub.rawGpsHorizUncertaintyM, "m", digits: 2) },
        .init(id: "rawGpsVertUncertaintyM", displayLabel: "Vert σ", group: .rawGps) { hub in formatUnit(hub.rawGpsVertUncertaintyM, "m", digits: 2) },
        .init(id: "rawGpsVelocityUncertaintyMS", displayLabel: "Vel σ", group: .rawGps) { hub in formatUnit(hub.rawGpsVelocityUncertaintyMS, "m/s", digits: 2) },
        .init(id: "rawGpsHeadingUncertaintyDeg", displayLabel: "Heading σ", group: .rawGps) { hub in formatUnit(hub.rawGpsHeadingUncertaintyDeg, "°", digits: 1) },
        .init(id: "rawGpsYawDeg", displayLabel: "Raw yaw", group: .rawGps) { hub in formatUnit(hub.rawGpsYawDeg, "°", digits: 1) },

        // MARK: RC
        .init(id: "rcIsAvailable", displayLabel: "Available", group: .rc) { hub in hub.rcIsAvailable.map(yesNo) },
        .init(id: "rcSignalStrengthPercent", displayLabel: "Signal", group: .rc) { hub in formatPercent(hub.rcSignalStrengthPercent) },
        .init(id: "rcWasAvailableOnce", displayLabel: "Ever bound", group: .rc) { hub in hub.rcWasAvailableOnce.map(yesNo) },

        // MARK: IMU
        .init(id: "imuAccelForwardMS2", displayLabel: "Accel fwd", group: .imu) { hub in formatUnit(hub.imuAccelForwardMS2, "m/s²", digits: 2) },
        .init(id: "imuAccelRightMS2", displayLabel: "Accel right", group: .imu) { hub in formatUnit(hub.imuAccelRightMS2, "m/s²", digits: 2) },
        .init(id: "imuAccelDownMS2", displayLabel: "Accel down", group: .imu) { hub in formatUnit(hub.imuAccelDownMS2, "m/s²", digits: 2) },
        .init(id: "imuGyroForwardRadS", displayLabel: "Gyro fwd", group: .imu) { hub in formatUnit(hub.imuGyroForwardRadS, "rad/s", digits: 3) },
        .init(id: "imuGyroRightRadS", displayLabel: "Gyro right", group: .imu) { hub in formatUnit(hub.imuGyroRightRadS, "rad/s", digits: 3) },
        .init(id: "imuGyroDownRadS", displayLabel: "Gyro down", group: .imu) { hub in formatUnit(hub.imuGyroDownRadS, "rad/s", digits: 3) },
        .init(id: "imuMagForwardGauss", displayLabel: "Mag fwd", group: .imu) { hub in formatUnit(hub.imuMagForwardGauss, "G", digits: 3) },
        .init(id: "imuMagRightGauss", displayLabel: "Mag right", group: .imu) { hub in formatUnit(hub.imuMagRightGauss, "G", digits: 3) },
        .init(id: "imuMagDownGauss", displayLabel: "Mag down", group: .imu) { hub in formatUnit(hub.imuMagDownGauss, "G", digits: 3) },
        .init(id: "imuTempDegC", displayLabel: "IMU temp", group: .imu) { hub in formatUnit(hub.imuTempDegC, "°C", digits: 1) },

        // MARK: Pressure
        .init(id: "scaledPressureAbsoluteHpa", displayLabel: "Absolute", group: .pressure) { hub in formatUnit(hub.scaledPressureAbsoluteHpa, "hPa", digits: 2) },
        .init(id: "scaledPressureDifferentialHpa", displayLabel: "Differential", group: .pressure) { hub in formatUnit(hub.scaledPressureDifferentialHpa, "hPa", digits: 2) },
        .init(id: "scaledPressureTempDegC", displayLabel: "Temp", group: .pressure) { hub in formatUnit(hub.scaledPressureTempDegC, "°C", digits: 1) },

        // MARK: Wind
        .init(id: "windNorthMS", displayLabel: "Wind N", group: .wind) { hub in formatUnit(hub.windNorthMS, "m/s", digits: 2) },
        .init(id: "windEastMS", displayLabel: "Wind E", group: .wind) { hub in formatUnit(hub.windEastMS, "m/s", digits: 2) },
        .init(id: "windDownMS", displayLabel: "Wind D", group: .wind) { hub in formatUnit(hub.windDownMS, "m/s", digits: 2) },

        // MARK: Distance sensor
        .init(id: "distanceCurrentM", displayLabel: "Current", group: .distance) { hub in formatUnit(hub.distanceCurrentM, "m", digits: 2) },
        .init(id: "distanceMinM", displayLabel: "Min", group: .distance) { hub in formatUnit(hub.distanceMinM, "m", digits: 2) },
        .init(id: "distanceMaxM", displayLabel: "Max", group: .distance) { hub in formatUnit(hub.distanceMaxM, "m", digits: 2) },

        // MARK: Fixed-wing / VTOL
        .init(id: "fixedWingAirspeedMS", displayLabel: "Airspeed", group: .fixedWingVTOL) { hub in formatUnit(hub.fixedWingAirspeedMS, "m/s", digits: 2) },
        .init(id: "fixedWingGroundspeedMS", displayLabel: "Groundspeed", group: .fixedWingVTOL) { hub in formatUnit(hub.fixedWingGroundspeedMS, "m/s", digits: 2) },
        .init(id: "fixedWingThrottlePercent", displayLabel: "Throttle", group: .fixedWingVTOL) { hub in formatPercent(hub.fixedWingThrottlePercent) },
        .init(id: "fixedWingClimbRateMS", displayLabel: "Climb rate", group: .fixedWingVTOL) { hub in formatUnit(hub.fixedWingClimbRateMS, "m/s", digits: 2) },
        .init(id: "fixedWingHeadingDeg", displayLabel: "Heading", group: .fixedWingVTOL) { hub in formatUnit(hub.fixedWingHeadingDeg, "°", digits: 1) },
        .init(id: "vtolState", displayLabel: "VTOL state", group: .fixedWingVTOL) { hub in hub.vtolState },

        // MARK: Odometry (compact)
        .init(id: "odometryFrameId", displayLabel: "Frame", group: .odometry) { hub in hub.odometryFrameId },
        .init(id: "odometryChildFrameId", displayLabel: "Child frame", group: .odometry) { hub in hub.odometryChildFrameId },
        .init(id: "odometryPosXM", displayLabel: "Pos X", group: .odometry) { hub in formatUnit(hub.odometryPosXM, "m", digits: 2) },
        .init(id: "odometryPosYM", displayLabel: "Pos Y", group: .odometry) { hub in formatUnit(hub.odometryPosYM, "m", digits: 2) },
        .init(id: "odometryPosZM", displayLabel: "Pos Z", group: .odometry) { hub in formatUnit(hub.odometryPosZM, "m", digits: 2) },

        // MARK: Status
        .init(id: "statusSeverity", displayLabel: "Severity", group: .status) { hub in hub.statusSeverity },
        .init(id: "statusText", displayLabel: "Last message", group: .status) { hub in
            let t = hub.statusText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return t?.isEmpty == false ? t : nil
        },
        .init(id: "lastBridgeEventType", displayLabel: "Last bridge event", group: .status) { hub in hub.lastBridgeEventType },

        // MARK: Time
        .init(id: "lastUpdate", displayLabel: "Last update", group: .time) { hub in
            hub.lastUpdate.formatted(date: .omitted, time: .standard)
        },
        .init(id: "unixEpochUs", displayLabel: "Autopilot epoch", group: .time) { hub in
            hub.unixEpochUs.map { "\($0) µs" }
        },
    ]

    /// Field IDs surfaced in each calibration system's right-column telemetry view.
    /// Returning `[]` (or only fields that resolve to `nil`) renders the
    /// "No additional telemetry fields available" placeholder in the UI.
    static func fields(forSystem id: FleetCalibrationSystemID) -> [Field] {
        let ids: [String]
        switch id {
        case .compass:
            ids = ["headingDeg", "healthMagnetometerCalibrationOk", "imuMagForwardGauss", "imuMagRightGauss", "imuMagDownGauss"]
        case .accelerometer:
            ids = ["healthAccelerometerCalibrationOk", "imuAccelForwardMS2", "imuAccelRightMS2", "imuAccelDownMS2", "imuTempDegC"]
        case .gyrometer:
            ids = ["healthGyrometerCalibrationOk", "imuGyroForwardRadS", "imuGyroRightRadS", "imuGyroDownRadS", "angularVelRollRadS", "angularVelPitchRadS", "angularVelYawRadS"]
        case .gps:
            ids = ["gpsNumSatellites", "gpsFixType", "healthGlobalPositionOk", "rawGpsHdop", "rawGpsVdop", "latitudeDeg", "longitudeDeg"]
        case .localPosition:
            ids = ["healthLocalPositionOk", "altitudeLocalM", "velocityNorthMS", "velocityEastMS", "velocityDownMS"]
        case .homePosition:
            ids = ["healthHomePositionOk", "homeLatitudeDeg", "homeLongitudeDeg", "homeAbsoluteAltM", "homeRelativeAltM"]
        case .rc:
            ids = ["rcIsAvailable", "rcSignalStrengthPercent", "rcWasAvailableOnce"]
        case .battery:
            ids = ["batteryRemainingPercent", "batteryVoltageV", "batteryCurrentA", "batteryCapacityConsumedAh", "batteryTimeRemainingS", "batteryTempDegC"]
        case .barometer:
            ids = ["scaledPressureAbsoluteHpa", "scaledPressureDifferentialHpa", "scaledPressureTempDegC", "altitudeAmslM"]
        case .ekf:
            ids = ["healthAllOk", "healthArmable", "healthGyrometerCalibrationOk", "healthAccelerometerCalibrationOk", "healthMagnetometerCalibrationOk", "healthLocalPositionOk", "healthGlobalPositionOk", "healthHomePositionOk"]
        default:
            ids = []
        }
        return ids.compactMap { fid in all.first { $0.id == fid } }
    }

    /// All catalogued field IDs (used by ``unknownFields(in:)`` to surface anything new under "Other").
    static let catalogedIds: Set<String> = Set(all.map(\.id))

    /// Free-text Mirror dump of any non-nil hub field whose property name is not catalogued.
    /// Renders alphabetised under the "Other" chip so adding new ``FleetHubVehicleTelemetry``
    /// fields never breaks completeness even before the catalog is updated.
    static func unknownFields(in hub: FleetHubVehicleTelemetry) -> [(id: String, displayLabel: String, value: String)] {
        Mirror(reflecting: hub).children.compactMap { child in
            guard let label = child.label, !catalogedIds.contains(label) else { return nil }
            let rendered = formatRawValue(child.value)
            guard rendered != "nil" else { return nil }
            return (label, label, rendered)
        }
        .sorted { $0.id < $1.id }
    }
}

// MARK: - Formatters

private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }

private func formatPercent(_ value: Double?) -> String? {
    guard let v = value, v.isFinite else { return nil }
    let normalised = v <= 1 ? v * 100 : v
    return "\(Int(round(normalised)))%"
}

private func formatUnit(_ value: Double?, _ unit: String, digits: Int) -> String? {
    guard let v = value, v.isFinite else { return nil }
    let formatted = String(format: "%.\(digits)f", v)
    return unit.isEmpty ? formatted : "\(formatted) \(unit)"
}

private func formatDeg(_ value: Double?, digits: Int) -> String? {
    guard let v = value, v.isFinite else { return nil }
    return String(format: "%.\(digits)f°", v)
}

private func formatSecondsAsDuration(_ seconds: Double?) -> String? {
    guard let s = seconds, s.isFinite, s >= 0 else { return nil }
    let total = Int(s.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let sec = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
}

private func formatRawValue(_ value: Any) -> String {
    let rendered = String(describing: value)
    if rendered.hasPrefix("Optional("), rendered.hasSuffix(")") {
        let inner = rendered.dropFirst("Optional(".count).dropLast()
        return String(inner)
    }
    return rendered
}
