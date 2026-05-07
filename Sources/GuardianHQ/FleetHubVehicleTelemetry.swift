import Foundation

/// Aggregated live telemetry for the first MAVLink system the Python bridge sees. Fields are filled opportunistically from
/// `mavsdk_bridge.py` JSON lines (`type` discriminates the payload); anything not yet received stays `nil`.
struct FleetHubVehicleTelemetry: Equatable {
    var lastUpdate: Date
    /// Last decoded bridge `type` (e.g. `battery`, `position`); useful for debugging stream health.
    var lastBridgeEventType: String?

    // MARK: Identity

    var autopilotStack: FleetAutopilotStack
    var flightSwMajor: Int?
    var flightSwMinor: Int?
    var flightSwPatch: Int?
    var flightSwGitHash: String?
    var osSwGitHash: String?
    var flightSwVersionType: String?

    // MARK: Core flight

    var isArmed: Bool
    var flightMode: String
    var inAir: Bool?
    var landedState: String?
    var healthAllOk: Bool?

    // MARK: Position (global)

    var latitudeDeg: Double?
    var longitudeDeg: Double?
    var absoluteAltM: Double?
    var relativeAltM: Double?

    // MARK: Home

    var homeLatitudeDeg: Double?
    var homeLongitudeDeg: Double?
    var homeAbsoluteAltM: Double?
    var homeRelativeAltM: Double?

    // MARK: Attitude & motion

    var rollDeg: Double?
    var pitchDeg: Double?
    var yawDeg: Double?
    var attitudeTimestampUs: UInt64?
    var headingDeg: Double?

    var quaternionW: Double?
    var quaternionX: Double?
    var quaternionY: Double?
    var quaternionZ: Double?
    var quaternionTimestampUs: UInt64?

    var angularVelRollRadS: Double?
    var angularVelPitchRadS: Double?
    var angularVelYawRadS: Double?

    var velocityNorthMS: Double?
    var velocityEastMS: Double?
    var velocityDownMS: Double?

    var positionVelNorthM: Double?
    var positionVelEastM: Double?
    var positionVelDownM: Double?
    var positionVelVnMS: Double?
    var positionVelVeMS: Double?
    var positionVelVdMS: Double?
    var positionVelHeadingDeg: Double?

    // MARK: Altitude breakdown

    var altitudeMonotonicM: Double?
    var altitudeAmslM: Double?
    var altitudeLocalM: Double?
    var altitudeRelativeM: Double?
    var altitudeTerrainM: Double?
    var altitudeBottomClearanceM: Double?

    // MARK: Battery

    var batteryId: UInt32?
    var batteryTempDegC: Double?
    var batteryVoltageV: Double?
    var batteryCurrentA: Double?
    var batteryCapacityConsumedAh: Double?
    var batteryRemainingPercent: Double?
    var batteryTimeRemainingS: Double?

    // MARK: GPS / raw GPS

    var gpsNumSatellites: Int32?
    var gpsFixType: String?

    var rawGpsTimestampUs: UInt64?
    var rawGpsLatitudeDeg: Double?
    var rawGpsLongitudeDeg: Double?
    var rawGpsAbsoluteAltM: Double?
    var rawGpsHdop: Double?
    var rawGpsVdop: Double?
    var rawGpsVelocityMS: Double?
    var rawGpsCogDeg: Double?
    var rawGpsAltitudeEllipsoidM: Double?
    var rawGpsHorizUncertaintyM: Double?
    var rawGpsVertUncertaintyM: Double?
    var rawGpsVelocityUncertaintyMS: Double?
    var rawGpsHeadingUncertaintyDeg: Double?
    var rawGpsYawDeg: Double?

    // MARK: Health flags

    var healthGyrometerCalibrationOk: Bool?
    var healthAccelerometerCalibrationOk: Bool?
    var healthMagnetometerCalibrationOk: Bool?
    var healthLocalPositionOk: Bool?
    var healthGlobalPositionOk: Bool?
    var healthHomePositionOk: Bool?
    var healthArmable: Bool?

    // MARK: Autopilot mission (MAVSDK native)

    /// `Mission.missionProgress.current` when ingested via MAVSDK (nil for bridge-only telemetry).
    var missionProgressCurrent: Int32?
    /// `Mission.missionProgress.total` when ingested via MAVSDK.
    var missionProgressTotal: Int32?

    // MARK: RC

    var rcWasAvailableOnce: Bool?
    var rcIsAvailable: Bool?
    var rcSignalStrengthPercent: Double?

    // MARK: Status text (last message)

    var statusSeverity: String?
    var statusText: String?

    // MARK: Sensors / environment

    var distanceMinM: Double?
    var distanceMaxM: Double?
    var distanceCurrentM: Double?
    var distanceOrientRollDeg: Double?
    var distanceOrientPitchDeg: Double?
    var distanceOrientYawDeg: Double?

    var windNorthMS: Double?
    var windEastMS: Double?
    var windDownMS: Double?

    var imuAccelForwardMS2: Double?
    var imuAccelRightMS2: Double?
    var imuAccelDownMS2: Double?
    var imuGyroForwardRadS: Double?
    var imuGyroRightRadS: Double?
    var imuGyroDownRadS: Double?
    var imuMagForwardGauss: Double?
    var imuMagRightGauss: Double?
    var imuMagDownGauss: Double?
    var imuTempDegC: Double?
    var imuTimestampUs: UInt64?

    var scaledPressureAbsoluteHpa: Double?
    var scaledPressureDifferentialHpa: Double?
    var scaledPressureTempDegC: Double?

    // MARK: Fixed-wing / VTOL

    var fixedWingAirspeedMS: Double?
    var fixedWingThrottlePercent: Double?
    var fixedWingClimbRateMS: Double?
    var fixedWingGroundspeedMS: Double?
    var fixedWingHeadingDeg: Double?
    var fixedWingAbsoluteAltM: Double?

    var vtolState: String?

    // MARK: Odometry (subset)

    var odometryTimeUsec: UInt64?
    var odometryFrameId: String?
    var odometryChildFrameId: String?
    var odometryPosXM: Double?
    var odometryPosYM: Double?
    var odometryPosZM: Double?
    var odometryQuatW: Double?
    var odometryQuatX: Double?
    var odometryQuatY: Double?
    var odometryQuatZ: Double?
    var odometryVelXMS: Double?
    var odometryVelYMS: Double?
    var odometryVelZMS: Double?

    // MARK: Time

    var unixEpochUs: UInt64?

    static let empty = FleetHubVehicleTelemetry(
        lastUpdate: Date(),
        lastBridgeEventType: nil,
        autopilotStack: .unknown,
        flightSwMajor: nil,
        flightSwMinor: nil,
        flightSwPatch: nil,
        flightSwGitHash: nil,
        osSwGitHash: nil,
        flightSwVersionType: nil,
        isArmed: false,
        flightMode: "—",
        inAir: nil,
        landedState: nil,
        healthAllOk: nil,
        latitudeDeg: nil,
        longitudeDeg: nil,
        absoluteAltM: nil,
        relativeAltM: nil,
        homeLatitudeDeg: nil,
        homeLongitudeDeg: nil,
        homeAbsoluteAltM: nil,
        homeRelativeAltM: nil,
        rollDeg: nil,
        pitchDeg: nil,
        yawDeg: nil,
        attitudeTimestampUs: nil,
        headingDeg: nil,
        quaternionW: nil,
        quaternionX: nil,
        quaternionY: nil,
        quaternionZ: nil,
        quaternionTimestampUs: nil,
        angularVelRollRadS: nil,
        angularVelPitchRadS: nil,
        angularVelYawRadS: nil,
        velocityNorthMS: nil,
        velocityEastMS: nil,
        velocityDownMS: nil,
        positionVelNorthM: nil,
        positionVelEastM: nil,
        positionVelDownM: nil,
        positionVelVnMS: nil,
        positionVelVeMS: nil,
        positionVelVdMS: nil,
        positionVelHeadingDeg: nil,
        altitudeMonotonicM: nil,
        altitudeAmslM: nil,
        altitudeLocalM: nil,
        altitudeRelativeM: nil,
        altitudeTerrainM: nil,
        altitudeBottomClearanceM: nil,
        batteryId: nil,
        batteryTempDegC: nil,
        batteryVoltageV: nil,
        batteryCurrentA: nil,
        batteryCapacityConsumedAh: nil,
        batteryRemainingPercent: nil,
        batteryTimeRemainingS: nil,
        gpsNumSatellites: nil,
        gpsFixType: nil,
        rawGpsTimestampUs: nil,
        rawGpsLatitudeDeg: nil,
        rawGpsLongitudeDeg: nil,
        rawGpsAbsoluteAltM: nil,
        rawGpsHdop: nil,
        rawGpsVdop: nil,
        rawGpsVelocityMS: nil,
        rawGpsCogDeg: nil,
        rawGpsAltitudeEllipsoidM: nil,
        rawGpsHorizUncertaintyM: nil,
        rawGpsVertUncertaintyM: nil,
        rawGpsVelocityUncertaintyMS: nil,
        rawGpsHeadingUncertaintyDeg: nil,
        rawGpsYawDeg: nil,
        healthGyrometerCalibrationOk: nil,
        healthAccelerometerCalibrationOk: nil,
        healthMagnetometerCalibrationOk: nil,
        healthLocalPositionOk: nil,
        healthGlobalPositionOk: nil,
        healthHomePositionOk: nil,
        healthArmable: nil,
        missionProgressCurrent: nil,
        missionProgressTotal: nil,
        rcWasAvailableOnce: nil,
        rcIsAvailable: nil,
        rcSignalStrengthPercent: nil,
        statusSeverity: nil,
        statusText: nil,
        distanceMinM: nil,
        distanceMaxM: nil,
        distanceCurrentM: nil,
        distanceOrientRollDeg: nil,
        distanceOrientPitchDeg: nil,
        distanceOrientYawDeg: nil,
        windNorthMS: nil,
        windEastMS: nil,
        windDownMS: nil,
        imuAccelForwardMS2: nil,
        imuAccelRightMS2: nil,
        imuAccelDownMS2: nil,
        imuGyroForwardRadS: nil,
        imuGyroRightRadS: nil,
        imuGyroDownRadS: nil,
        imuMagForwardGauss: nil,
        imuMagRightGauss: nil,
        imuMagDownGauss: nil,
        imuTempDegC: nil,
        imuTimestampUs: nil,
        scaledPressureAbsoluteHpa: nil,
        scaledPressureDifferentialHpa: nil,
        scaledPressureTempDegC: nil,
        fixedWingAirspeedMS: nil,
        fixedWingThrottlePercent: nil,
        fixedWingClimbRateMS: nil,
        fixedWingGroundspeedMS: nil,
        fixedWingHeadingDeg: nil,
        fixedWingAbsoluteAltM: nil,
        vtolState: nil,
        odometryTimeUsec: nil,
        odometryFrameId: nil,
        odometryChildFrameId: nil,
        odometryPosXM: nil,
        odometryPosYM: nil,
        odometryPosZM: nil,
        odometryQuatW: nil,
        odometryQuatX: nil,
        odometryQuatY: nil,
        odometryQuatZ: nil,
        odometryVelXMS: nil,
        odometryVelYMS: nil,
        odometryVelZMS: nil,
        unixEpochUs: nil
    )

    /// Summarizes the subset shown in fleet cards and other compact UI.
    func telemetrySnapshot() -> FleetTelemetrySnapshot {
        FleetTelemetrySnapshot(
            isArmed: isArmed,
            flightMode: flightMode,
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            relativeAltM: relativeAltM,
            lastUpdate: lastUpdate,
            autopilotStack: autopilotStack
        )
    }
}

// MARK: - Bridge JSON (flat envelope; only fields present for a given `type` are non-nil)

struct BridgeHubEnvelope: Decodable {
    let type: String
    var vehicleId: String?
    var systemId: Int?
    var stack: String?
    var armed: Bool?
    var flightMode: String?
    var latDeg: Double?
    var lonDeg: Double?
    var relAltM: Double?
    var absAltM: Double?
    var message: String?
    var host: String?
    var port: Int?

    var batteryId: UInt32?
    var batteryTempDegc: Double?
    var batteryVoltageV: Double?
    var batteryCurrentA: Double?
    var batteryCapacityConsumedAh: Double?
    var batteryRemainingPct: Double?
    var batteryTimeRemainingS: Double?

    var gpsNumSatellites: Int32?
    var gpsFixType: String?

    var healthGyrometerCalibrationOk: Bool?
    var healthAccelerometerCalibrationOk: Bool?
    var healthMagnetometerCalibrationOk: Bool?
    var healthLocalPositionOk: Bool?
    var healthGlobalPositionOk: Bool?
    var healthHomePositionOk: Bool?
    var healthArmable: Bool?
    var healthAllOk: Bool?

    var inAir: Bool?
    var landedState: String?

    var rcWasAvailableOnce: Bool?
    var rcIsAvailable: Bool?
    var rcSignalStrengthPct: Double?

    var rollDeg: Double?
    var pitchDeg: Double?
    var yawDeg: Double?
    var attitudeTimestampUs: UInt64?

    var northMS: Double?
    var eastMS: Double?
    var downMS: Double?

    var altMonotonicM: Double?
    var altAmslM: Double?
    var altLocalM: Double?
    var altRelativeM: Double?
    var altTerrainM: Double?
    var altBottomClearanceM: Double?

    var homeLatDeg: Double?
    var homeLonDeg: Double?
    var homeAbsAltM: Double?
    var homeRelAltM: Double?

    var statusSeverity: String?
    var statusText: String?

    var posVelNorthM: Double?
    var posVelEastM: Double?
    var posVelDownM: Double?
    var posVelVnMS: Double?
    var posVelVeMS: Double?
    var posVelVdMS: Double?
    var posVelHdgDeg: Double?

    var headingDeg: Double?

    var quatW: Double?
    var quatX: Double?
    var quatY: Double?
    var quatZ: Double?
    var quatTimestampUs: UInt64?

    var angVelRollRadS: Double?
    var angVelPitchRadS: Double?
    var angVelYawRadS: Double?

    var distMinM: Double?
    var distMaxM: Double?
    var distCurM: Double?
    var distOrientRollDeg: Double?
    var distOrientPitchDeg: Double?
    var distOrientYawDeg: Double?

    var windXNedMS: Double?
    var windYNedMS: Double?
    var windZNedMS: Double?

    var imuAccFwd: Double?
    var imuAccRight: Double?
    var imuAccDown: Double?
    var imuGyroFwd: Double?
    var imuGyroRight: Double?
    var imuGyroDown: Double?
    var imuMagFwd: Double?
    var imuMagRight: Double?
    var imuMagDown: Double?
    var imuTempDegc: Double?
    var imuTimestampUs: UInt64?

    var pressAbsHpa: Double?
    var pressDiffHpa: Double?
    var pressTempDegc: Double?

    var fwAirspeedMS: Double?
    var fwThrottlePct: Double?
    var fwClimbMS: Double?
    var fwGspeedMS: Double?
    var fwHeadingDeg: Double?
    var fwAbsAltM: Double?

    var vtolState: String?

    var odomUsec: UInt64?
    var odomFrame: String?
    var odomChildFrame: String?
    var odomPx: Double?
    var odomPy: Double?
    var odomPz: Double?
    var odomQw: Double?
    var odomQx: Double?
    var odomQy: Double?
    var odomQz: Double?
    var odomVx: Double?
    var odomVy: Double?
    var odomVz: Double?

    var rawGpsTimestampUs: UInt64?
    var rawGpsLatDeg: Double?
    var rawGpsLonDeg: Double?
    var rawGpsAbsAltM: Double?
    var rawGpsHdop: Double?
    var rawGpsVdop: Double?
    var rawGpsVelMS: Double?
    var rawGpsCogDeg: Double?
    var rawGpsAltEllipsoidM: Double?
    var rawGpsHorizUncM: Double?
    var rawGpsVertUncM: Double?
    var rawGpsVelUncMS: Double?
    var rawGpsHdgUncDeg: Double?
    var rawGpsYawDeg: Double?

    var unixEpochUs: UInt64?

    var flightSwMajor: Int?
    var flightSwMinor: Int?
    var flightSwPatch: Int?
    var flightSwGitHash: String?
    var osSwGitHash: String?
    var flightSwVersionType: String?

    private enum CodingKeys: String, CodingKey {
        case type, vehicleId, systemId, stack, armed, flightMode, latDeg, lonDeg, relAltM, absAltM, message, host, port
        case batteryId, batteryTempDegc, batteryVoltageV, batteryCurrentA, batteryCapacityConsumedAh
        case batteryRemainingPct, batteryTimeRemainingS
        case gpsNumSatellites, gpsFixType
        case healthGyrometerCalibrationOk, healthAccelerometerCalibrationOk, healthMagnetometerCalibrationOk
        case healthLocalPositionOk, healthGlobalPositionOk, healthHomePositionOk, healthArmable, healthAllOk
        case inAir, landedState
        case rcWasAvailableOnce, rcIsAvailable, rcSignalStrengthPct
        case rollDeg, pitchDeg, yawDeg, attitudeTimestampUs
        case northMS, eastMS, downMS
        case altMonotonicM, altAmslM, altLocalM, altRelativeM, altTerrainM, altBottomClearanceM
        case homeLatDeg, homeLonDeg, homeAbsAltM, homeRelAltM
        case statusSeverity, statusText
        case posVelNorthM, posVelEastM, posVelDownM, posVelVnMS, posVelVeMS, posVelVdMS, posVelHdgDeg
        case headingDeg
        case quatW, quatX, quatY, quatZ, quatTimestampUs
        case angVelRollRadS, angVelPitchRadS, angVelYawRadS
        case distMinM, distMaxM, distCurM, distOrientRollDeg, distOrientPitchDeg, distOrientYawDeg
        case windXNedMS, windYNedMS, windZNedMS
        case imuAccFwd, imuAccRight, imuAccDown, imuGyroFwd, imuGyroRight, imuGyroDown
        case imuMagFwd, imuMagRight, imuMagDown, imuTempDegc, imuTimestampUs
        case pressAbsHpa, pressDiffHpa, pressTempDegc
        case fwAirspeedMS, fwThrottlePct, fwClimbMS, fwGspeedMS, fwHeadingDeg, fwAbsAltM
        case vtolState
        case odomUsec, odomFrame, odomChildFrame, odomPx, odomPy, odomPz, odomQw, odomQx, odomQy, odomQz
        case odomVx, odomVy, odomVz
        case rawGpsTimestampUs, rawGpsLatDeg, rawGpsLonDeg, rawGpsAbsAltM, rawGpsHdop, rawGpsVdop
        case rawGpsVelMS, rawGpsCogDeg, rawGpsAltEllipsoidM, rawGpsHorizUncM, rawGpsVertUncM
        case rawGpsVelUncMS, rawGpsHdgUncDeg, rawGpsYawDeg
        case unixEpochUs
        case flightSwMajor, flightSwMinor, flightSwPatch, flightSwGitHash, osSwGitHash, flightSwVersionType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        vehicleId = try c.decodeIfPresent(String.self, forKey: .vehicleId)
        systemId = try c.decodeIfPresent(Int.self, forKey: .systemId)
        stack = try c.decodeIfPresent(String.self, forKey: .stack)
        armed = try c.decodeIfPresent(Bool.self, forKey: .armed)
        flightMode = try c.decodeIfPresent(String.self, forKey: .flightMode)
        latDeg = try c.decodeIfPresent(Double.self, forKey: .latDeg)
        lonDeg = try c.decodeIfPresent(Double.self, forKey: .lonDeg)
        relAltM = try c.decodeIfPresent(Double.self, forKey: .relAltM)
        absAltM = try c.decodeIfPresent(Double.self, forKey: .absAltM)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        host = try c.decodeIfPresent(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        batteryId = try c.decodeIfPresent(UInt32.self, forKey: .batteryId)
        batteryTempDegc = try c.decodeIfPresent(Double.self, forKey: .batteryTempDegc)
        batteryVoltageV = try c.decodeIfPresent(Double.self, forKey: .batteryVoltageV)
        batteryCurrentA = try c.decodeIfPresent(Double.self, forKey: .batteryCurrentA)
        batteryCapacityConsumedAh = try c.decodeIfPresent(Double.self, forKey: .batteryCapacityConsumedAh)
        batteryRemainingPct = try c.decodeIfPresent(Double.self, forKey: .batteryRemainingPct)
        batteryTimeRemainingS = try c.decodeIfPresent(Double.self, forKey: .batteryTimeRemainingS)
        gpsNumSatellites = try c.decodeIfPresent(Int32.self, forKey: .gpsNumSatellites)
        gpsFixType = try c.decodeIfPresent(String.self, forKey: .gpsFixType)
        healthGyrometerCalibrationOk = try c.decodeIfPresent(Bool.self, forKey: .healthGyrometerCalibrationOk)
        healthAccelerometerCalibrationOk = try c.decodeIfPresent(Bool.self, forKey: .healthAccelerometerCalibrationOk)
        healthMagnetometerCalibrationOk = try c.decodeIfPresent(Bool.self, forKey: .healthMagnetometerCalibrationOk)
        healthLocalPositionOk = try c.decodeIfPresent(Bool.self, forKey: .healthLocalPositionOk)
        healthGlobalPositionOk = try c.decodeIfPresent(Bool.self, forKey: .healthGlobalPositionOk)
        healthHomePositionOk = try c.decodeIfPresent(Bool.self, forKey: .healthHomePositionOk)
        healthArmable = try c.decodeIfPresent(Bool.self, forKey: .healthArmable)
        healthAllOk = try c.decodeIfPresent(Bool.self, forKey: .healthAllOk)
        inAir = try c.decodeIfPresent(Bool.self, forKey: .inAir)
        landedState = try c.decodeIfPresent(String.self, forKey: .landedState)
        rcWasAvailableOnce = try c.decodeIfPresent(Bool.self, forKey: .rcWasAvailableOnce)
        rcIsAvailable = try c.decodeIfPresent(Bool.self, forKey: .rcIsAvailable)
        rcSignalStrengthPct = try c.decodeIfPresent(Double.self, forKey: .rcSignalStrengthPct)
        rollDeg = try c.decodeIfPresent(Double.self, forKey: .rollDeg)
        pitchDeg = try c.decodeIfPresent(Double.self, forKey: .pitchDeg)
        yawDeg = try c.decodeIfPresent(Double.self, forKey: .yawDeg)
        attitudeTimestampUs = try c.decodeIfPresent(UInt64.self, forKey: .attitudeTimestampUs)
        northMS = try c.decodeIfPresent(Double.self, forKey: .northMS)
        eastMS = try c.decodeIfPresent(Double.self, forKey: .eastMS)
        downMS = try c.decodeIfPresent(Double.self, forKey: .downMS)
        altMonotonicM = try c.decodeIfPresent(Double.self, forKey: .altMonotonicM)
        altAmslM = try c.decodeIfPresent(Double.self, forKey: .altAmslM)
        altLocalM = try c.decodeIfPresent(Double.self, forKey: .altLocalM)
        altRelativeM = try c.decodeIfPresent(Double.self, forKey: .altRelativeM)
        altTerrainM = try c.decodeIfPresent(Double.self, forKey: .altTerrainM)
        altBottomClearanceM = try c.decodeIfPresent(Double.self, forKey: .altBottomClearanceM)
        homeLatDeg = try c.decodeIfPresent(Double.self, forKey: .homeLatDeg)
        homeLonDeg = try c.decodeIfPresent(Double.self, forKey: .homeLonDeg)
        homeAbsAltM = try c.decodeIfPresent(Double.self, forKey: .homeAbsAltM)
        homeRelAltM = try c.decodeIfPresent(Double.self, forKey: .homeRelAltM)
        statusSeverity = try c.decodeIfPresent(String.self, forKey: .statusSeverity)
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
        posVelNorthM = try c.decodeIfPresent(Double.self, forKey: .posVelNorthM)
        posVelEastM = try c.decodeIfPresent(Double.self, forKey: .posVelEastM)
        posVelDownM = try c.decodeIfPresent(Double.self, forKey: .posVelDownM)
        posVelVnMS = try c.decodeIfPresent(Double.self, forKey: .posVelVnMS)
        posVelVeMS = try c.decodeIfPresent(Double.self, forKey: .posVelVeMS)
        posVelVdMS = try c.decodeIfPresent(Double.self, forKey: .posVelVdMS)
        posVelHdgDeg = try c.decodeIfPresent(Double.self, forKey: .posVelHdgDeg)
        headingDeg = try c.decodeIfPresent(Double.self, forKey: .headingDeg)
        quatW = try c.decodeIfPresent(Double.self, forKey: .quatW)
        quatX = try c.decodeIfPresent(Double.self, forKey: .quatX)
        quatY = try c.decodeIfPresent(Double.self, forKey: .quatY)
        quatZ = try c.decodeIfPresent(Double.self, forKey: .quatZ)
        quatTimestampUs = try c.decodeIfPresent(UInt64.self, forKey: .quatTimestampUs)
        angVelRollRadS = try c.decodeIfPresent(Double.self, forKey: .angVelRollRadS)
        angVelPitchRadS = try c.decodeIfPresent(Double.self, forKey: .angVelPitchRadS)
        angVelYawRadS = try c.decodeIfPresent(Double.self, forKey: .angVelYawRadS)
        distMinM = try c.decodeIfPresent(Double.self, forKey: .distMinM)
        distMaxM = try c.decodeIfPresent(Double.self, forKey: .distMaxM)
        distCurM = try c.decodeIfPresent(Double.self, forKey: .distCurM)
        distOrientRollDeg = try c.decodeIfPresent(Double.self, forKey: .distOrientRollDeg)
        distOrientPitchDeg = try c.decodeIfPresent(Double.self, forKey: .distOrientPitchDeg)
        distOrientYawDeg = try c.decodeIfPresent(Double.self, forKey: .distOrientYawDeg)
        windXNedMS = try c.decodeIfPresent(Double.self, forKey: .windXNedMS)
        windYNedMS = try c.decodeIfPresent(Double.self, forKey: .windYNedMS)
        windZNedMS = try c.decodeIfPresent(Double.self, forKey: .windZNedMS)
        imuAccFwd = try c.decodeIfPresent(Double.self, forKey: .imuAccFwd)
        imuAccRight = try c.decodeIfPresent(Double.self, forKey: .imuAccRight)
        imuAccDown = try c.decodeIfPresent(Double.self, forKey: .imuAccDown)
        imuGyroFwd = try c.decodeIfPresent(Double.self, forKey: .imuGyroFwd)
        imuGyroRight = try c.decodeIfPresent(Double.self, forKey: .imuGyroRight)
        imuGyroDown = try c.decodeIfPresent(Double.self, forKey: .imuGyroDown)
        imuMagFwd = try c.decodeIfPresent(Double.self, forKey: .imuMagFwd)
        imuMagRight = try c.decodeIfPresent(Double.self, forKey: .imuMagRight)
        imuMagDown = try c.decodeIfPresent(Double.self, forKey: .imuMagDown)
        imuTempDegc = try c.decodeIfPresent(Double.self, forKey: .imuTempDegc)
        imuTimestampUs = try c.decodeIfPresent(UInt64.self, forKey: .imuTimestampUs)
        pressAbsHpa = try c.decodeIfPresent(Double.self, forKey: .pressAbsHpa)
        pressDiffHpa = try c.decodeIfPresent(Double.self, forKey: .pressDiffHpa)
        pressTempDegc = try c.decodeIfPresent(Double.self, forKey: .pressTempDegc)
        fwAirspeedMS = try c.decodeIfPresent(Double.self, forKey: .fwAirspeedMS)
        fwThrottlePct = try c.decodeIfPresent(Double.self, forKey: .fwThrottlePct)
        fwClimbMS = try c.decodeIfPresent(Double.self, forKey: .fwClimbMS)
        fwGspeedMS = try c.decodeIfPresent(Double.self, forKey: .fwGspeedMS)
        fwHeadingDeg = try c.decodeIfPresent(Double.self, forKey: .fwHeadingDeg)
        fwAbsAltM = try c.decodeIfPresent(Double.self, forKey: .fwAbsAltM)
        vtolState = try c.decodeIfPresent(String.self, forKey: .vtolState)
        odomUsec = try c.decodeIfPresent(UInt64.self, forKey: .odomUsec)
        odomFrame = try c.decodeIfPresent(String.self, forKey: .odomFrame)
        odomChildFrame = try c.decodeIfPresent(String.self, forKey: .odomChildFrame)
        odomPx = try c.decodeIfPresent(Double.self, forKey: .odomPx)
        odomPy = try c.decodeIfPresent(Double.self, forKey: .odomPy)
        odomPz = try c.decodeIfPresent(Double.self, forKey: .odomPz)
        odomQw = try c.decodeIfPresent(Double.self, forKey: .odomQw)
        odomQx = try c.decodeIfPresent(Double.self, forKey: .odomQx)
        odomQy = try c.decodeIfPresent(Double.self, forKey: .odomQy)
        odomQz = try c.decodeIfPresent(Double.self, forKey: .odomQz)
        odomVx = try c.decodeIfPresent(Double.self, forKey: .odomVx)
        odomVy = try c.decodeIfPresent(Double.self, forKey: .odomVy)
        odomVz = try c.decodeIfPresent(Double.self, forKey: .odomVz)
        rawGpsTimestampUs = try c.decodeIfPresent(UInt64.self, forKey: .rawGpsTimestampUs)
        rawGpsLatDeg = try c.decodeIfPresent(Double.self, forKey: .rawGpsLatDeg)
        rawGpsLonDeg = try c.decodeIfPresent(Double.self, forKey: .rawGpsLonDeg)
        rawGpsAbsAltM = try c.decodeIfPresent(Double.self, forKey: .rawGpsAbsAltM)
        rawGpsHdop = try c.decodeIfPresent(Double.self, forKey: .rawGpsHdop)
        rawGpsVdop = try c.decodeIfPresent(Double.self, forKey: .rawGpsVdop)
        rawGpsVelMS = try c.decodeIfPresent(Double.self, forKey: .rawGpsVelMS)
        rawGpsCogDeg = try c.decodeIfPresent(Double.self, forKey: .rawGpsCogDeg)
        rawGpsAltEllipsoidM = try c.decodeIfPresent(Double.self, forKey: .rawGpsAltEllipsoidM)
        rawGpsHorizUncM = try c.decodeIfPresent(Double.self, forKey: .rawGpsHorizUncM)
        rawGpsVertUncM = try c.decodeIfPresent(Double.self, forKey: .rawGpsVertUncM)
        rawGpsVelUncMS = try c.decodeIfPresent(Double.self, forKey: .rawGpsVelUncMS)
        rawGpsHdgUncDeg = try c.decodeIfPresent(Double.self, forKey: .rawGpsHdgUncDeg)
        rawGpsYawDeg = try c.decodeIfPresent(Double.self, forKey: .rawGpsYawDeg)
        unixEpochUs = try c.decodeIfPresent(UInt64.self, forKey: .unixEpochUs)
        flightSwMajor = try c.decodeIfPresent(Int.self, forKey: .flightSwMajor)
        flightSwMinor = try c.decodeIfPresent(Int.self, forKey: .flightSwMinor)
        flightSwPatch = try c.decodeIfPresent(Int.self, forKey: .flightSwPatch)
        flightSwGitHash = try c.decodeIfPresent(String.self, forKey: .flightSwGitHash)
        osSwGitHash = try c.decodeIfPresent(String.self, forKey: .osSwGitHash)
        flightSwVersionType = try c.decodeIfPresent(String.self, forKey: .flightSwVersionType)
    }
}

extension FleetHubVehicleTelemetry {
    /// Merges one decoded bridge line into this hub. Callers should set `lastUpdate` after this if needed.
    mutating func merge(_ env: BridgeHubEnvelope) {
        lastBridgeEventType = env.type

        switch env.type {
        case "vehicle_stack":
            if let raw = env.stack?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               let parsed = FleetAutopilotStack(rawValue: raw) {
                autopilotStack = parsed
            }
        case "vehicle_version":
            if let v = env.flightSwMajor { flightSwMajor = v }
            if let v = env.flightSwMinor { flightSwMinor = v }
            if let v = env.flightSwPatch { flightSwPatch = v }
            if let v = env.flightSwGitHash { flightSwGitHash = v }
            if let v = env.osSwGitHash { osSwGitHash = v }
            if let v = env.flightSwVersionType { flightSwVersionType = v }
        case "armed":
            if let v = env.armed { isArmed = v }
        case "flight_mode":
            if let v = env.flightMode { flightMode = v }
        case "position":
            if let v = env.latDeg { latitudeDeg = v }
            if let v = env.lonDeg { longitudeDeg = v }
            if let v = env.relAltM { relativeAltM = v }
            if let v = env.absAltM { absoluteAltM = v }
        case "battery":
            if let v = env.batteryId { batteryId = v }
            if let v = env.batteryTempDegc { batteryTempDegC = v }
            if let v = env.batteryVoltageV { batteryVoltageV = v }
            if let v = env.batteryCurrentA { batteryCurrentA = v }
            if let v = env.batteryCapacityConsumedAh { batteryCapacityConsumedAh = v }
            if let v = env.batteryRemainingPct { batteryRemainingPercent = v }
            if let v = env.batteryTimeRemainingS { batteryTimeRemainingS = v }
        case "gps_info":
            if let v = env.gpsNumSatellites { gpsNumSatellites = v }
            if let v = env.gpsFixType { gpsFixType = v }
        case "health":
            if let v = env.healthGyrometerCalibrationOk { healthGyrometerCalibrationOk = v }
            if let v = env.healthAccelerometerCalibrationOk { healthAccelerometerCalibrationOk = v }
            if let v = env.healthMagnetometerCalibrationOk { healthMagnetometerCalibrationOk = v }
            if let v = env.healthLocalPositionOk { healthLocalPositionOk = v }
            if let v = env.healthGlobalPositionOk { healthGlobalPositionOk = v }
            if let v = env.healthHomePositionOk { healthHomePositionOk = v }
            if let v = env.healthArmable { healthArmable = v }
        case "health_all_ok":
            if let v = env.healthAllOk { healthAllOk = v }
        case "in_air":
            if let v = env.inAir { inAir = v }
        case "landed_state":
            if let v = env.landedState { landedState = v }
        case "rc_status":
            if let v = env.rcWasAvailableOnce { rcWasAvailableOnce = v }
            if let v = env.rcIsAvailable { rcIsAvailable = v }
            if let v = env.rcSignalStrengthPct { rcSignalStrengthPercent = v }
        case "attitude_euler":
            if let v = env.rollDeg { rollDeg = v }
            if let v = env.pitchDeg { pitchDeg = v }
            if let v = env.yawDeg { yawDeg = v }
            if let v = env.attitudeTimestampUs { attitudeTimestampUs = v }
        case "attitude_quaternion":
            if let v = env.quatW { quaternionW = v }
            if let v = env.quatX { quaternionX = v }
            if let v = env.quatY { quaternionY = v }
            if let v = env.quatZ { quaternionZ = v }
            if let v = env.quatTimestampUs { quaternionTimestampUs = v }
        case "attitude_angular_velocity_body":
            if let v = env.angVelRollRadS { angularVelRollRadS = v }
            if let v = env.angVelPitchRadS { angularVelPitchRadS = v }
            if let v = env.angVelYawRadS { angularVelYawRadS = v }
        case "velocity_ned":
            if let v = env.northMS { velocityNorthMS = v }
            if let v = env.eastMS { velocityEastMS = v }
            if let v = env.downMS { velocityDownMS = v }
        case "altitude":
            if let v = env.altMonotonicM { altitudeMonotonicM = v }
            if let v = env.altAmslM { altitudeAmslM = v }
            if let v = env.altLocalM { altitudeLocalM = v }
            if let v = env.altRelativeM { altitudeRelativeM = v }
            if let v = env.altTerrainM { altitudeTerrainM = v }
            if let v = env.altBottomClearanceM { altitudeBottomClearanceM = v }
        case "home":
            if let v = env.homeLatDeg { homeLatitudeDeg = v }
            if let v = env.homeLonDeg { homeLongitudeDeg = v }
            if let v = env.homeAbsAltM { homeAbsoluteAltM = v }
            if let v = env.homeRelAltM { homeRelativeAltM = v }
        case "status_text":
            if let v = env.statusSeverity { statusSeverity = v }
            if let v = env.statusText { statusText = v }
        case "position_velocity_ned":
            if let v = env.posVelNorthM { positionVelNorthM = v }
            if let v = env.posVelEastM { positionVelEastM = v }
            if let v = env.posVelDownM { positionVelDownM = v }
            if let v = env.posVelVnMS { positionVelVnMS = v }
            if let v = env.posVelVeMS { positionVelVeMS = v }
            if let v = env.posVelVdMS { positionVelVdMS = v }
            if let v = env.posVelHdgDeg { positionVelHeadingDeg = v }
        case "heading":
            if let v = env.headingDeg { headingDeg = v }
        case "distance_sensor":
            if let v = env.distMinM { distanceMinM = v }
            if let v = env.distMaxM { distanceMaxM = v }
            if let v = env.distCurM { distanceCurrentM = v }
            if let v = env.distOrientRollDeg { distanceOrientRollDeg = v }
            if let v = env.distOrientPitchDeg { distanceOrientPitchDeg = v }
            if let v = env.distOrientYawDeg { distanceOrientYawDeg = v }
        case "wind":
            if let v = env.windXNedMS { windNorthMS = v }
            if let v = env.windYNedMS { windEastMS = v }
            if let v = env.windZNedMS { windDownMS = v }
        case "imu":
            if let v = env.imuAccFwd { imuAccelForwardMS2 = v }
            if let v = env.imuAccRight { imuAccelRightMS2 = v }
            if let v = env.imuAccDown { imuAccelDownMS2 = v }
            if let v = env.imuGyroFwd { imuGyroForwardRadS = v }
            if let v = env.imuGyroRight { imuGyroRightRadS = v }
            if let v = env.imuGyroDown { imuGyroDownRadS = v }
            if let v = env.imuMagFwd { imuMagForwardGauss = v }
            if let v = env.imuMagRight { imuMagRightGauss = v }
            if let v = env.imuMagDown { imuMagDownGauss = v }
            if let v = env.imuTempDegc { imuTempDegC = v }
            if let v = env.imuTimestampUs { imuTimestampUs = v }
        case "scaled_pressure":
            if let v = env.pressAbsHpa { scaledPressureAbsoluteHpa = v }
            if let v = env.pressDiffHpa { scaledPressureDifferentialHpa = v }
            if let v = env.pressTempDegc { scaledPressureTempDegC = v }
        case "fixedwing_metrics":
            if let v = env.fwAirspeedMS { fixedWingAirspeedMS = v }
            if let v = env.fwThrottlePct { fixedWingThrottlePercent = v }
            if let v = env.fwClimbMS { fixedWingClimbRateMS = v }
            if let v = env.fwGspeedMS { fixedWingGroundspeedMS = v }
            if let v = env.fwHeadingDeg { fixedWingHeadingDeg = v }
            if let v = env.fwAbsAltM { fixedWingAbsoluteAltM = v }
        case "vtol_state":
            if let v = env.vtolState { vtolState = v }
        case "odometry":
            if let v = env.odomUsec { odometryTimeUsec = v }
            if let v = env.odomFrame { odometryFrameId = v }
            if let v = env.odomChildFrame { odometryChildFrameId = v }
            if let v = env.odomPx { odometryPosXM = v }
            if let v = env.odomPy { odometryPosYM = v }
            if let v = env.odomPz { odometryPosZM = v }
            if let v = env.odomQw { odometryQuatW = v }
            if let v = env.odomQx { odometryQuatX = v }
            if let v = env.odomQy { odometryQuatY = v }
            if let v = env.odomQz { odometryQuatZ = v }
            if let v = env.odomVx { odometryVelXMS = v }
            if let v = env.odomVy { odometryVelYMS = v }
            if let v = env.odomVz { odometryVelZMS = v }
        case "raw_gps":
            if let v = env.rawGpsTimestampUs { rawGpsTimestampUs = v }
            if let v = env.rawGpsLatDeg { rawGpsLatitudeDeg = v }
            if let v = env.rawGpsLonDeg { rawGpsLongitudeDeg = v }
            if let v = env.rawGpsAbsAltM { rawGpsAbsoluteAltM = v }
            if let v = env.rawGpsHdop { rawGpsHdop = v }
            if let v = env.rawGpsVdop { rawGpsVdop = v }
            if let v = env.rawGpsVelMS { rawGpsVelocityMS = v }
            if let v = env.rawGpsCogDeg { rawGpsCogDeg = v }
            if let v = env.rawGpsAltEllipsoidM { rawGpsAltitudeEllipsoidM = v }
            if let v = env.rawGpsHorizUncM { rawGpsHorizUncertaintyM = v }
            if let v = env.rawGpsVertUncM { rawGpsVertUncertaintyM = v }
            if let v = env.rawGpsVelUncMS { rawGpsVelocityUncertaintyMS = v }
            if let v = env.rawGpsHdgUncDeg { rawGpsHeadingUncertaintyDeg = v }
            if let v = env.rawGpsYawDeg { rawGpsYawDeg = v }
        case "unix_epoch_time":
            if let v = env.unixEpochUs { unixEpochUs = v }
        default:
            break
        }
    }
}
