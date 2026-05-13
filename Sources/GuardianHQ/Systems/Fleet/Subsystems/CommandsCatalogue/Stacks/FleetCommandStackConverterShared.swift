import Foundation
import Mavsdk

// MARK: - Shared helpers for stack converters

/// Stack-agnostic helpers used by ``FleetCommandStackConverterArduPilot`` and
/// ``FleetCommandStackConverterPX4``. Anything that depends on autopilot dialect lives
/// in the stack-specific converter; anything that operates over the normalised
/// ``FleetHubVehicleTelemetry`` snapshot lives here.
enum FleetCommandStackConverterShared {

    // MARK: - get.telemetry.* — immediate reads from hub telemetry

    /// Translates a `command.fleet.vehicle.get.telemetry.*` name into an immediate
    /// response built from the supplied hub telemetry snapshot. Returns `nil` when the
    /// supplied name is not a supported telemetry-get name (caller falls through to
    /// `.notImplemented`).
    static func translateGetTelemetry(
        commandName: FleetCommandName,
        hub: FleetHubVehicleTelemetry?,
        elapsed: TimeInterval = 0
    ) -> FleetCommandStackTranslation? {

        guard let hub else {
            // The vehicle is connected (catalogue invoke verified `.live`) but the
            // hub has not produced a sample yet. Recipes can branch on `notConnected`.
            switch commandName {
            case .fleetVehicleGetTelemetryBattery,
                 .fleetVehicleGetTelemetryCompass,
                 .fleetVehicleGetTelemetryGps,
                 .fleetVehicleGetTelemetryEstimator,
                 .fleetVehicleGetTelemetryFlight,
                 .fleetVehicleGetTelemetryRc,
                 .fleetVehicleGetTelemetryLink,
                 .fleetVehicleGetTelemetryMode:
                return .immediate(
                    .error(
                        .notConnected,
                        detail: "No hub telemetry sample yet for this vehicle.",
                        elapsed: elapsed
                    )
                )
            default:
                return nil
            }
        }

        switch commandName {
        case .fleetVehicleGetTelemetryBattery:
            return .immediate(
                .success(
                    detail: "Battery snapshot",
                    payload: .keyValues(batteryKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryCompass:
            return .immediate(
                .success(
                    detail: "Compass snapshot",
                    payload: .keyValues(compassKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryGps:
            return .immediate(
                .success(
                    detail: "GPS snapshot",
                    payload: .keyValues(gpsKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryEstimator:
            return .immediate(
                .success(
                    detail: "Estimator snapshot",
                    payload: .keyValues(estimatorKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryFlight:
            return .immediate(
                .success(
                    detail: "Flight-state snapshot",
                    payload: .keyValues(flightKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryRc:
            return .immediate(
                .success(
                    detail: "RC snapshot",
                    payload: .keyValues(rcKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryLink:
            return .immediate(
                .success(
                    detail: "Link snapshot",
                    payload: .keyValues(linkKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        case .fleetVehicleGetTelemetryMode:
            return .immediate(
                .success(
                    detail: "Mode snapshot",
                    payload: .keyValues(modeKeyValues(hub: hub)),
                    elapsed: elapsed
                )
            )

        default:
            return nil
        }
    }

    // MARK: - Telemetry → key/value payloads

    /// Renders an optional value into the key/value dictionary, omitting it when `nil`.
    /// Keeps payloads tight by not emitting `"key=nil"` rows.
    private static func put<T>(
        _ key: String,
        _ value: T?,
        into dict: inout [String: String],
        formatter: (T) -> String
    ) {
        guard let value else { return }
        dict[key] = formatter(value)
    }

    private static func formatDouble(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.numberStyle = .decimal
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    private static func batteryKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        var d: [String: String] = [:]
        put("voltageV", hub.batteryVoltageV, into: &d, formatter: formatDouble)
        put("currentA", hub.batteryCurrentA, into: &d, formatter: formatDouble)
        put("remainingPercent", hub.batteryRemainingPercent, into: &d, formatter: formatDouble)
        put("timeRemainingS", hub.batteryTimeRemainingS, into: &d, formatter: formatDouble)
        return d
    }

    private static func compassKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        var d: [String: String] = [:]
        put("headingDeg", hub.headingDeg, into: &d, formatter: formatDouble)
        return d
    }

    private static func gpsKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        var d: [String: String] = [:]
        put("fixType", hub.gpsFixType, into: &d, formatter: { $0 })
        put("altitudeAmslM", hub.altitudeAmslM, into: &d, formatter: formatDouble)
        put("altitudeLocalM", hub.altitudeLocalM, into: &d, formatter: formatDouble)
        return d
    }

    private static func estimatorKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        // Reflect everything that looks like a `health*` flag so we don't have to
        // mirror the FleetHubVehicleTelemetry definition every time it grows.
        let mirror = Mirror(reflecting: hub)
        var d: [String: String] = [:]
        for child in mirror.children {
            guard let label = child.label, label.hasPrefix("health") else { continue }
            if let bool = child.value as? Bool {
                d[label] = bool ? "true" : "false"
            } else if let optBool = child.value as? Bool? {
                if let unwrapped = optBool {
                    d[label] = unwrapped ? "true" : "false"
                }
            }
        }
        return d
    }

    private static func flightKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        let mirror = Mirror(reflecting: hub)
        var d: [String: String] = [:]
        let interesting: Set<String> = ["isArmed", "isInAir", "modeText", "armedTimeS"]
        for child in mirror.children {
            guard let label = child.label, interesting.contains(label) else { continue }
            d[label] = describeChildValue(child.value)
        }
        return d
    }

    private static func rcKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        let mirror = Mirror(reflecting: hub)
        var d: [String: String] = [:]
        for child in mirror.children {
            guard let label = child.label,
                  label.lowercased().contains("rc") else { continue }
            d[label] = describeChildValue(child.value)
        }
        return d
    }

    private static func linkKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        let mirror = Mirror(reflecting: hub)
        var d: [String: String] = [:]
        let interesting: Set<String> = [
            "lastUpdate", "autopilotStack", "flightSwMajor",
            "linkQualityPercent", "rxBytesPerSecond", "txBytesPerSecond"
        ]
        for child in mirror.children {
            guard let label = child.label, interesting.contains(label) else { continue }
            d[label] = describeChildValue(child.value)
        }
        return d
    }

    private static func modeKeyValues(hub: FleetHubVehicleTelemetry) -> [String: String] {
        let mirror = Mirror(reflecting: hub)
        var d: [String: String] = [:]
        for child in mirror.children {
            guard let label = child.label,
                  label == "modeText" || label == "autopilotStack" else { continue }
            d[label] = describeChildValue(child.value)
        }
        return d
    }

    private static func describeChildValue(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let inner = mirror.children.first?.value {
                return describeChildValue(inner)
            }
            return "—"
        }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let int = value as? Int { return String(int) }
        if let int64 = value as? Int64 { return String(int64) }
        if let dbl = value as? Double { return formatDouble(dbl) }
        if let str = value as? String { return str }
        return String(describing: value)
    }

    // MARK: - do.mission.upload — JSON-string parameter → MAVSDK mission items

    /// Translate `command.fleet.vehicle.do.mission.upload` into one or more vehicle
    /// commands: optionally ``FleetVehicleCommand/uploadGeofence(polygons:)`` (when
    /// `geofencePolygonsJSON` decodes to a non-empty list), then
    /// ``FleetVehicleCommand/uploadMission(items:)``.
    ///
    /// Returns `.notImplemented` when the parameter is missing or the JSON does not
    /// decode — recipes / callers see the failure detail and can branch.
    static func translateMissionUpload(
        parameters: FleetCommandParameters
    ) -> FleetCommandStackTranslation {
        guard let json = parameters.string(named: "missionItemsJSON") else {
            return .notImplemented(
                detail: "do.mission.upload requires a `missionItemsJSON` string parameter."
            )
        }
        do {
            let items = try FleetVehicleCommandMissionItemPayload.decodeMissionItems(fromJSON: json)
            var commands: [FleetVehicleCommand] = []
            if let fenceJSON = parameters.string(named: "geofencePolygonsJSON") {
                let trimmed = fenceJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed != "[]" {
                    let polys = try FleetVehicleCommandGeofencePolygonPayload.decodePolygons(fromJSON: fenceJSON)
                    if !polys.isEmpty {
                        commands.append(.uploadGeofence(polygons: polys))
                    }
                }
            }
            commands.append(.uploadMission(items: items))
            return .vehicleCommands(commands)
        } catch {
            return .notImplemented(
                detail: "do.mission.upload: failed to decode missionItemsJSON or geofencePolygonsJSON: \(error.localizedDescription)"
            )
        }
    }

    /// MAVSDK ``Geofence`` upload / clear catalogue verbs (shared by ArduPilot and PX4).
    static func translateFleetVehicleGeofenceIfNeeded(
        commandName: FleetCommandName,
        parameters: FleetCommandParameters
    ) -> FleetCommandStackTranslation? {
        switch commandName {
        case .fleetVehicleDoGeofenceUpload:
            guard let json = parameters.string(named: "geofencePolygonsJSON") else {
                return .notImplemented(
                    detail: "do.geofence.upload requires a `geofencePolygonsJSON` string parameter."
                )
            }
            do {
                let polys = try FleetVehicleCommandGeofencePolygonPayload.decodePolygons(fromJSON: json)
                guard !polys.isEmpty else {
                    return .notImplemented(
                        detail: "do.geofence.upload requires at least one valid polygon after decoding (got none)."
                    )
                }
                return .vehicleCommands([.uploadGeofence(polygons: polys)])
            } catch {
                return .notImplemented(
                    detail: "do.geofence.upload: failed to decode geofencePolygonsJSON: \(error.localizedDescription)"
                )
            }
        case .fleetVehicleDoGeofenceClear:
            return .vehicleCommands([.clearGeofence])
        default:
            return nil
        }
    }

    /// Mission plugin catalogue commands shared by PX4, ArduPilot, and stack-unknown
    /// (all use the same MAVSDK `Mission` surface). Returns `nil` when `commandName` is
    /// not part of the mission command family.
    static func translateFleetVehicleMissionIfNeeded(
        commandName: FleetCommandName,
        parameters: FleetCommandParameters
    ) -> FleetCommandStackTranslation? {

        switch commandName {

        case .fleetVehicleDoMissionUpload:
            return translateMissionUpload(parameters: parameters)

        case .fleetVehicleDoMissionClear:
            return .vehicleCommands([.missionClear])

        case .fleetVehicleDoMissionStart:
            return .vehicleCommands([.missionStart])

        case .fleetVehicleDoMissionPause:
            return .vehicleCommands([.missionPause])

        case .fleetVehicleDoMissionJumpTo:
            let rawIndex = parameters.integer(named: "missionItemIndex") ?? parameters.integer(named: "index")
            guard let rawIndex else {
                return .notImplemented(
                    detail: "do.mission.jump.to requires an integer `index` (or `missionItemIndex`) parameter."
                )
            }
            let clamped = Int32(clamping: rawIndex)
            return .vehicleCommands([.missionSetCurrentItem(index: clamped)])

        case .fleetVehicleDoMissionDownload:
            return .vehicleCommands([.missionDownloadPlanJSON])

        case .fleetVehicleDoMissionUploadWithProgress:
            return .notImplemented(
                detail: "Mission upload with progress (`uploadMissionWithProgress`) is not wired in Guardian v1 — Observable streams are not folded into the Layer 0 Completable pipeline yet."
            )

        case .fleetVehicleDoMissionDownloadWithProgress:
            return .notImplemented(
                detail: "Mission download with progress (`downloadMissionWithProgress`) is not wired in Guardian v1 — Observable streams are not folded into the Layer 0 Completable pipeline yet."
            )

        case .fleetVehicleCancelMissionUpload:
            return .vehicleCommands([.cancelMissionUpload])

        case .fleetVehicleCancelMissionDownload:
            return .vehicleCommands([.cancelMissionDownload])

        case .fleetVehicleGetMissionFinished:
            return .vehicleCommands([.missionIsFinishedQuery])

        case .fleetVehicleGetMissionRtlAfter:
            return .vehicleCommands([.missionGetRtlAfter])

        case .fleetVehicleDoMissionRtlAfterSet:
            guard let enable = parameters.bool(named: "enable") else {
                return .notImplemented(
                    detail: "do.mission.rtl.after.set requires a boolean `enable` parameter."
                )
            }
            return .vehicleCommands([.missionSetRtlAfter(enable: enable)])

        default:
            return nil
        }
    }

    // MARK: - do.move.altitude — datum-aware climb/descend at current lat/lon

    /// Translate `command.fleet.vehicle.do.move.altitude` into a `[.gotoCoordinate(...)]`
    /// dispatch using current lat/lon. Because ``FleetVehicleCommand/gotoCoordinate(_:relativeAltitudeM:yawDeg:)``
    /// passes its altitude as **a delta added to the vehicle's current absolute altitude**
    /// (see `FleetLinkService.executeVehicleCommand` → `Action.gotoLocation`), we resolve
    /// the absolute target here and emit the equivalent delta.
    ///
    /// Datums:
    /// * `asl` / `msl` — `meters` is interpreted as AMSL. Treated as equivalent because
    ///   MAVSDK reports a single `absoluteAltitudeM` and most autopilots fold MSL and
    ///   AMSL into one number; differentiation would require geoid-offset readback the
    ///   catalogue does not have.
    /// * `agl` — `meters` is interpreted as height above launch home. Ground AMSL is
    ///   derived from `absoluteAltM − relativeAltM`. Requires both telemetry fields.
    ///
    /// Yaw is preserved at the vehicle's current heading where known, otherwise 0 —
    /// `do.move.altitude` is an altitude-only operation and must not impose a yaw
    /// rotation as a side-effect.
    static func translateMoveAltitude(
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation {

        guard let meters = parameters.double(named: "meters") else {
            return .notImplemented(detail: "do.move.altitude requires a `meters` parameter.")
        }
        guard let datumRaw = parameters.string(named: "datum") else {
            return .notImplemented(detail: "do.move.altitude requires a `datum` parameter.")
        }
        guard let datum = FleetVehicleCoreCommandAltitudeDatum(rawValue: datumRaw) else {
            return .notImplemented(detail: "do.move.altitude datum '\(datumRaw)' is not recognised.")
        }

        guard
            let lat = context.hubTelemetry?.latitudeDeg,
            let lon = context.hubTelemetry?.longitudeDeg,
            let currentAbs = context.hubTelemetry?.absoluteAltM
        else {
            return .immediate(
                .error(
                    .notConnected,
                    detail: "do.move.altitude needs current lat/lon and absolute altitude from hub telemetry — none cached yet for this vehicle.",
                    elapsed: 0
                )
            )
        }

        let targetAbsM: Double
        switch datum {
        case .asl, .msl:
            targetAbsM = meters
        case .agl:
            guard let currentRel = context.hubTelemetry?.relativeAltM else {
                return .immediate(
                    .error(
                        .notConnected,
                        detail: "do.move.altitude datum=agl needs hub relativeAltM (height above launch) — none cached yet for this vehicle.",
                        elapsed: 0
                    )
                )
            }
            targetAbsM = (currentAbs - currentRel) + meters
        }

        let deltaM = targetAbsM - currentAbs
        let yawDeg = context.hubTelemetry?.headingDeg ?? 0

        return .vehicleCommands([
            .gotoCoordinate(
                RouteCoordinate(lat: lat, lon: lon),
                relativeAltitudeM: deltaM,
                yawDeg: yawDeg
            )
        ])
    }

    // MARK: - do.move.heading — horizontal translation along bearing

    /// Translate `command.fleet.vehicle.do.move.heading` into a `[.gotoCoordinate(...)]`
    /// dispatch that offsets the current lat/lon by `distanceM` metres along
    /// `headingDegrees`, keeping altitude unchanged. Yaw is set to the heading so the
    /// vehicle faces the direction of travel.
    ///
    /// Uses the spherical great-circle formula. For the metre-to-kilometre scales this
    /// command targets the error stays well below GPS resolution; we intentionally do
    /// not pull in a Vincenty/WGS-84 implementation.
    static func translateMoveHeading(
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation {

        guard let distanceM = parameters.double(named: "distanceM") else {
            return .notImplemented(detail: "do.move.heading requires a `distanceM` parameter.")
        }
        guard let headingDegrees = parameters.double(named: "headingDegrees") else {
            return .notImplemented(detail: "do.move.heading requires a `headingDegrees` parameter.")
        }

        guard
            let lat = context.hubTelemetry?.latitudeDeg,
            let lon = context.hubTelemetry?.longitudeDeg
        else {
            return .immediate(
                .error(
                    .notConnected,
                    detail: "do.move.heading needs current lat/lon from hub telemetry — none cached yet for this vehicle.",
                    elapsed: 0
                )
            )
        }

        let (newLat, newLon) = offsetLatLon(
            latitudeDeg: lat,
            longitudeDeg: lon,
            distanceM: distanceM,
            bearingDeg: headingDegrees
        )

        return .vehicleCommands([
            .gotoCoordinate(
                RouteCoordinate(lat: newLat, lon: newLon),
                relativeAltitudeM: 0,
                yawDeg: headingDegrees
            )
        ])
    }

    /// Spherical great-circle offset: given a start lat/lon, a distance in metres and
    /// a bearing in degrees, return the destination lat/lon. Mean Earth radius is
    /// used; over the ranges this command targets the resulting error is well below
    /// GPS resolution.
    private static func offsetLatLon(
        latitudeDeg: Double,
        longitudeDeg: Double,
        distanceM: Double,
        bearingDeg: Double
    ) -> (lat: Double, lon: Double) {
        let earthRadiusM = 6_371_000.0
        let bearingRad = bearingDeg * .pi / 180
        let lat1 = latitudeDeg * .pi / 180
        let lon1 = longitudeDeg * .pi / 180
        let angularDistance = distanceM / earthRadiusM
        let lat2 = asin(
            sin(lat1) * cos(angularDistance)
            + cos(lat1) * sin(angularDistance) * cos(bearingRad)
        )
        let lon2 = lon1 + atan2(
            sin(bearingRad) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        return (lat: lat2 * 180 / .pi, lon: lon2 * 180 / .pi)
    }

    // MARK: - do.move.point — pointKind + (optional) explicit lat/lon

    /// Translate `command.fleet.vehicle.do.move.point` into a `[.gotoCoordinate(...)]`
    /// dispatch. Lives in shared because the lat/lon resolution rules (telemetry vs
    /// explicit, home / rally still unwired) are stack-agnostic.
    ///
    /// * `currentLatLon` — pulls lat/lon from the latest hub telemetry snapshot.
    /// * `explicit` — requires `latitudeDeg` / `longitudeDeg` parameters.
    /// * `home` / `rally` — `.notImplemented` until home / rally readback exists.
    ///
    /// Always requires `relativeAltitudeM`. `yawDeg` defaults to 0 when missing.
    ///
    /// **Ground / surface (UGV / USV):** when hub lat/lon is available and the explicit
    /// target is not coincident with the hub, the emitted `gotoCoordinate` yaw is the
    /// great-circle **bearing** hub → target. MAVSDK `gotoLocation` couples heading with
    /// the horizontal setpoint on skid-steer rovers; reusing the vehicle's current yaw
    /// while the position setpoint differs yields yaw-in-place. Callers may still pass
    /// `yawDeg` for the coincident / no-telemetry fallback.
    static func translateMovePoint(
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation {

        guard let kindRaw = parameters.string(named: "pointKind") else {
            return .notImplemented(detail: "do.move.point requires a `pointKind` parameter.")
        }
        guard let kind = FleetVehicleCoreCommandPointKind(rawValue: kindRaw) else {
            return .notImplemented(detail: "do.move.point pointKind '\(kindRaw)' is not recognised.")
        }
        guard let relativeAltitudeM = parameters.double(named: "relativeAltitudeM") else {
            return .notImplemented(detail: "do.move.point requires a `relativeAltitudeM` parameter.")
        }
        let yawDeg = parameters.double(named: "yawDeg") ?? 0.0

        switch kind {
        case .explicit:
            guard
                let lat = parameters.double(named: "latitudeDeg"),
                let lon = parameters.double(named: "longitudeDeg")
            else {
                return .notImplemented(
                    detail: "do.move.point pointKind=explicit requires latitudeDeg and longitudeDeg parameters."
                )
            }
            let effectiveYaw = Self.yawDegForMovePointGoto(
                requestedYawDeg: yawDeg,
                targetLat: lat,
                targetLon: lon,
                vehicleClass: context.vehicleType.universalClass,
                hub: context.hubTelemetry
            )
            return .vehicleCommands([
                .gotoCoordinate(
                    RouteCoordinate(lat: lat, lon: lon),
                    relativeAltitudeM: relativeAltitudeM,
                    yawDeg: effectiveYaw
                )
            ])

        case .currentLatLon:
            guard
                let lat = context.hubTelemetry?.latitudeDeg,
                let lon = context.hubTelemetry?.longitudeDeg
            else {
                return .immediate(
                    .error(
                        .notConnected,
                        detail: "do.move.point pointKind=currentLatLon needs hub telemetry lat/lon — none cached yet for this vehicle.",
                        elapsed: 0
                    )
                )
            }
            return .vehicleCommands([
                .gotoCoordinate(
                    RouteCoordinate(lat: lat, lon: lon),
                    relativeAltitudeM: relativeAltitudeM,
                    yawDeg: yawDeg
                )
            ])

        case .home:
            return .notImplemented(detail: "do.move.point pointKind=home not yet wired (no autopilot home readback bridged into hub telemetry).")
        case .rally:
            return .notImplemented(detail: "do.move.point pointKind=rally not yet wired (no autopilot rally-point readback bridged into hub telemetry).")
        }
    }

    /// Yaw sent with ``FleetVehicleCommand/gotoCoordinate`` for `do.move.point`.
    private static func yawDegForMovePointGoto(
        requestedYawDeg: Double,
        targetLat: Double,
        targetLon: Double,
        vehicleClass: UniversalVehicleClass,
        hub: FleetHubVehicleTelemetry?
    ) -> Double {
        switch vehicleClass {
        case .ugv, .usv:
            guard let hLat = hub?.latitudeDeg, let hLon = hub?.longitudeDeg else {
                return requestedYawDeg
            }
            let separationM = MissionTelemetryGeo.horizontalDistanceM(
                lat1: hLat,
                lon1: hLon,
                lat2: targetLat,
                lon2: targetLon
            )
            guard separationM > 0.5 else { return requestedYawDeg }
            return MissionTelemetryGeo.bearingDegrees(
                lat1: hLat,
                lon1: hLon,
                lat2: targetLat,
                lon2: targetLon
            )
        case .uav, .uuv, .unknown:
            return requestedYawDeg
        }
    }

    // MARK: - Mode-string translation (do.mode)

    /// Maps the catalogue's stack-agnostic `mode` parameter value to a real
    /// `FleetVehicleCommand.setMode(...)` invocation. Per-stack dispatch happens
    /// inside `FleetLinkService.completionForSetMode(...)` — PX4 sends a raw MAVLink
    /// SET_MODE via `Px4ModeCommander`, ArduPilot sends `mode <name>` via the MAVSDK
    /// Shell plugin, and stack-`unknown` falls back from AP shell to PX4 raw. Returns
    /// `nil` only when the supplied `raw` string is not a known mode token (caller
    /// surfaces `.notImplemented`).
    static func vehicleCommands(forModeValue raw: String) -> [FleetVehicleCommand]? {
        guard let mode = FleetVehicleMode(rawValue: raw) else { return nil }
        return [.setMode(mode)]
    }

    // MARK: - Outcome normalisation (shared heuristics)

    /// Generic, stack-agnostic outcome → response mapping. Both PX4 and ArduPilot
    /// converters call into this and override only when a stack-specific keyword
    /// changes the classification (e.g. ArduPilot's "PreArm:" prefix).
    static func normaliseOutcome(
        _ outcome: FleetCommandAsyncOutcome,
        commandName: FleetCommandName,
        elapsed: TimeInterval
    ) -> FleetCommandResponse {

        switch outcome {
        case .succeeded:
            return .success(detail: nil, payload: .empty, elapsed: elapsed)

        case .succeededWithPayload(let payload):
            return .success(detail: nil, payload: payload, elapsed: elapsed)

        case .failed(let raw):
            // Calibration commands have a typed cancellation path: the recipe layer
            // (or the operator UI) runs `cancel.calibration` in parallel, MAVSDK's
            // in-flight calibration observable surfaces an `onError` that mentions
            // cancellation, and we map that to ``FleetCommandResponse/Outcome/cancelled``
            // rather than `.error(.unknown)`. Gated on the calibration command names
            // so unrelated commands whose failure happens to contain "cancel" are not
            // misidentified.
            if isCalibrationCommand(commandName),
               FleetLinkService.isCalibrationCancellationDetail(raw) {
                return .cancelled(detail: raw, elapsed: elapsed)
            }
            let lower = raw.lowercased()
            let kind = classify(failureMessage: lower, commandName: commandName)
            return .error(kind, detail: raw, elapsed: elapsed)
        }
    }

    /// `true` when the command's outcome should be filtered through the calibration
    /// cancellation heuristic above. Covers both the `do.calibrate.*` family and the
    /// dedicated `cancel.calibration` command.
    private static func isCalibrationCommand(_ name: FleetCommandName) -> Bool {
        let raw = name.rawValue
        return raw.contains(".do.calibrate.") || raw == "command.fleet.vehicle.cancel.calibration"
    }

    /// Heuristic classifier for failure strings. **Best-effort** in v1 — both stacks
    /// produce free-form strings today; first-class typed errors from
    /// `FleetLinkService` are a follow-on.
    private static func classify(
        failureMessage lower: String,
        commandName: FleetCommandName
    ) -> FleetCommandErrorKind {

        // Catalogue-level routing failures (all bubble through MAVSDK Completable
        // failures or our own appendVehicleLog wrappers).
        //
        // PARAM_SET read-back mismatch is emitted by
        // ``FleetLinkService.completionForSetParameterFloatWithReadBack`` /
        // ``completionForSetParameterIntWithReadBack`` whenever a follow-up
        // `getParam*` does not match the requested value. Surface as a typed kind so
        // recipes can branch on silent clamps / locked params without parsing the
        // raw string.
        if lower.contains("param_set read-back mismatch") {
            return .parameterReadBackMismatch
        }
        if lower.contains("no vehicle model") || lower.contains("no vehicle.") {
            return .noVehicle
        }
        if lower.contains("no mavsdk session") || lower.contains("not connected") {
            return .noSession
        }
        if lower.contains("authority gate") || lower.contains("rejected: authority")
            || lower.contains("live drive has no active session") {
            return .authorityGated
        }
        if lower.contains("timed out") {
            return .unknown
        }

        // Vehicle-side common phrasings.
        if lower.contains("already armed") {
            return commandName == .fleetVehicleDoArm ? .alreadyArmed : .unknown
        }
        if lower.contains("already disarmed") {
            return commandName == .fleetVehicleDoDisarm ? .alreadyDisarmed : .unknown
        }
        if lower.contains("calibration") {
            // Distinguish "calibration declined / not started" from "did not converge"
            // when the message is explicit about which.
            if lower.contains("converge") || lower.contains("failed mid") {
                return .calibrationDidNotConverge
            }
            return .calibrationDeclined
        }
        if lower.contains("mode") && (lower.contains("not supported") || lower.contains("unsupported")) {
            return .modeNotSupported
        }
        if lower.contains("busy") || lower.contains("autopilot is busy") {
            return .autopilotBusy
        }
        if lower.contains("permission denied") || lower.contains("denied") {
            // For arm, treat as autopilot rejection. For everything else, generic.
            if commandName == .fleetVehicleDoArm {
                return .armRejectedByAutopilot
            }
            return .dispatchFailed
        }
        if lower.contains("rejected") || lower.contains("refused") {
            if commandName == .fleetVehicleDoArm {
                return .armRejectedByAutopilot
            }
            return .dispatchFailed
        }

        return .unknown
    }
}

// MARK: - Codable mirror for Mavsdk.Mission.MissionItem

/// JSON-portable mirror of `Mavsdk.Mission.MissionItem`. The MAVSDK type itself is not
/// `Codable` (RPC-generated, contains internal RPC bridges), so the catalogue accepts
/// `command.fleet.vehicle.do.mission.upload`'s `missionItemsJSON` parameter as an array
/// of these structs and the shared converter rebuilds real MAVSDK items at translation
/// time.
///
/// All field names match the MAVSDK constructor argument labels so the JSON round-trip
/// is one-to-one with the MAVSDK API. `cameraAction` is encoded as the string token of
/// the enum case (`"none"`, `"takePhoto"`, …) for human readability.
struct FleetVehicleCommandMissionItemPayload: Codable, Equatable, Sendable {
    var latitudeDeg: Double
    var longitudeDeg: Double
    var relativeAltitudeM: Double
    var speedMS: Double
    var isFlyThrough: Bool
    var gimbalPitchDeg: Double
    var gimbalYawDeg: Double
    var cameraAction: String
    var loiterTimeS: Double
    var cameraPhotoIntervalS: Double
    var acceptanceRadiusM: Double
    var yawDeg: Double
    var cameraPhotoDistanceM: Double

    /// Memberwise initializer for catalogue JSON and tests (``init(mavsdk:)`` is the other entry point).
    init(
        latitudeDeg: Double,
        longitudeDeg: Double,
        relativeAltitudeM: Double,
        speedMS: Double,
        isFlyThrough: Bool,
        gimbalPitchDeg: Double,
        gimbalYawDeg: Double,
        cameraAction: String,
        loiterTimeS: Double,
        cameraPhotoIntervalS: Double,
        acceptanceRadiusM: Double,
        yawDeg: Double,
        cameraPhotoDistanceM: Double
    ) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.relativeAltitudeM = relativeAltitudeM
        self.speedMS = speedMS
        self.isFlyThrough = isFlyThrough
        self.gimbalPitchDeg = gimbalPitchDeg
        self.gimbalYawDeg = gimbalYawDeg
        self.cameraAction = cameraAction
        self.loiterTimeS = loiterTimeS
        self.cameraPhotoIntervalS = cameraPhotoIntervalS
        self.acceptanceRadiusM = acceptanceRadiusM
        self.yawDeg = yawDeg
        self.cameraPhotoDistanceM = cameraPhotoDistanceM
    }

    /// Decode a JSON array string into a list of MAVSDK mission items.
    static func decodeMissionItems(fromJSON json: String) throws -> [Mavsdk.Mission.MissionItem] {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missionItemsJSON is not valid UTF-8.")
            )
        }
        let payloads = try JSONDecoder().decode([FleetVehicleCommandMissionItemPayload].self, from: data)
        return payloads.map { $0.mavsdkMissionItem }
    }

    /// Build the MAVSDK item, mapping `cameraAction` strings to the enum's cases. Any
    /// unrecognised camera action token falls back to `.none` rather than crashing the
    /// recipe — the caller can sanity-check via the `equivalentCameraActionToken`
    /// helper before encoding.
    var mavsdkMissionItem: Mavsdk.Mission.MissionItem {
        Mavsdk.Mission.MissionItem(
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            relativeAltitudeM: Float(relativeAltitudeM),
            speedMS: Float(speedMS),
            isFlyThrough: isFlyThrough,
            gimbalPitchDeg: Float(gimbalPitchDeg),
            gimbalYawDeg: Float(gimbalYawDeg),
            cameraAction: Self.cameraAction(fromToken: cameraAction),
            loiterTimeS: Float(loiterTimeS),
            cameraPhotoIntervalS: cameraPhotoIntervalS,
            acceptanceRadiusM: Float(acceptanceRadiusM),
            yawDeg: Float(yawDeg),
            cameraPhotoDistanceM: Float(cameraPhotoDistanceM)
        )
    }

    private static func cameraAction(fromToken token: String) -> Mavsdk.Mission.MissionItem.CameraAction {
        switch token {
        case "none": return .none
        case "takePhoto": return .takePhoto
        case "startPhotoInterval": return .startPhotoInterval
        case "stopPhotoInterval": return .stopPhotoInterval
        case "startVideo": return .startVideo
        case "stopVideo": return .stopVideo
        case "startPhotoDistance": return .startPhotoDistance
        case "stopPhotoDistance": return .stopPhotoDistance
        default:
            let unrecognizedPrefix = "unrecognized_"
            if token.hasPrefix(unrecognizedPrefix) {
                let suffix = String(token.dropFirst(unrecognizedPrefix.count))
                if let code = Int(suffix) {
                    return .UNRECOGNIZED(code)
                }
            }
            return .none
        }
    }

    init(mavsdk item: Mavsdk.Mission.MissionItem) {
        latitudeDeg = item.latitudeDeg
        longitudeDeg = item.longitudeDeg
        relativeAltitudeM = Double(item.relativeAltitudeM)
        speedMS = Double(item.speedMS)
        isFlyThrough = item.isFlyThrough
        gimbalPitchDeg = Double(item.gimbalPitchDeg)
        gimbalYawDeg = Double(item.gimbalYawDeg)
        cameraAction = Self.cameraActionToken(item.cameraAction)
        loiterTimeS = Double(item.loiterTimeS)
        cameraPhotoIntervalS = item.cameraPhotoIntervalS
        acceptanceRadiusM = Double(item.acceptanceRadiusM)
        yawDeg = Double(item.yawDeg)
        cameraPhotoDistanceM = Double(item.cameraPhotoDistanceM)
    }

    private static func cameraActionToken(_ action: Mavsdk.Mission.MissionItem.CameraAction) -> String {
        switch action {
        case .none: return "none"
        case .takePhoto: return "takePhoto"
        case .startPhotoInterval: return "startPhotoInterval"
        case .stopPhotoInterval: return "stopPhotoInterval"
        case .startVideo: return "startVideo"
        case .stopVideo: return "stopVideo"
        case .startPhotoDistance: return "startPhotoDistance"
        case .stopPhotoDistance: return "stopPhotoDistance"
        case .UNRECOGNIZED(let code):
            return "unrecognized_\(code)"
        }
    }

    /// Encode a downloaded MAVSDK plan into the same JSON array shape accepted by
    /// ``decodeMissionItems(fromJSON:)`` / `do.mission.upload`.
    static func encodeMissionPlanToJSON(plan: Mavsdk.Mission.MissionPlan) throws -> String {
        let payloads = plan.missionItems.map { FleetVehicleCommandMissionItemPayload(mavsdk: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payloads)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                payloads,
                .init(codingPath: [], debugDescription: "Encoded mission JSON is not valid UTF-8.")
            )
        }
        return string
    }
}

// MARK: - Codable mirror for Mavsdk.Geofence.Polygon

/// JSON-portable mirror of ``Mavsdk.Geofence/Polygon`` for `geofencePolygonsJSON` on
/// ``FleetCommandName/fleetVehicleDoMissionUpload`` and ``FleetCommandName/fleetVehicleDoGeofenceUpload``.
struct FleetVehicleCommandGeofencePolygonPayload: Codable, Equatable, Sendable {
    var fenceType: String
    var points: [FleetVehicleCommandGeofencePointPayload]

    init(fenceType: String, points: [FleetVehicleCommandGeofencePointPayload]) {
        self.fenceType = fenceType
        self.points = points
    }

    init(mavsdk polygon: Mavsdk.Geofence.Polygon) {
        fenceType = Self.fenceTypeToken(polygon.fenceType)
        points = polygon.points.map { FleetVehicleCommandGeofencePointPayload(mavsdk: $0) }
    }

    var mavsdkPolygon: Mavsdk.Geofence.Polygon {
        Mavsdk.Geofence.Polygon(points: points.map(\.mavsdkPoint), fenceType: Self.fenceType(fromToken: fenceType))
    }

    static func decodePolygons(fromJSON json: String) throws -> [Mavsdk.Geofence.Polygon] {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "geofencePolygonsJSON is not valid UTF-8.")
            )
        }
        let payloads = try JSONDecoder().decode([FleetVehicleCommandGeofencePolygonPayload].self, from: data)
        return payloads.map(\.mavsdkPolygon)
    }

    static func encodePolygonsToJSON(polygons: [Mavsdk.Geofence.Polygon]) throws -> String {
        let payloads = polygons.map { FleetVehicleCommandGeofencePolygonPayload(mavsdk: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payloads)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                payloads,
                .init(codingPath: [], debugDescription: "Encoded geofence JSON is not valid UTF-8.")
            )
        }
        return string
    }

    private static func fenceType(fromToken token: String) -> Mavsdk.Geofence.Polygon.FenceType {
        switch token {
        case "inclusion": return .inclusion
        case "exclusion": return .exclusion
        default:
            let unrecognizedPrefix = "unrecognized_"
            if token.hasPrefix(unrecognizedPrefix) {
                let suffix = String(token.dropFirst(unrecognizedPrefix.count))
                if let code = Int(suffix) {
                    return .UNRECOGNIZED(code)
                }
            }
            return .inclusion
        }
    }

    private static func fenceTypeToken(_ t: Mavsdk.Geofence.Polygon.FenceType) -> String {
        switch t {
        case .inclusion: return "inclusion"
        case .exclusion: return "exclusion"
        case .UNRECOGNIZED(let code):
            return "unrecognized_\(code)"
        }
    }
}

struct FleetVehicleCommandGeofencePointPayload: Codable, Equatable, Sendable {
    var latitudeDeg: Double
    var longitudeDeg: Double

    init(latitudeDeg: Double, longitudeDeg: Double) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
    }

    init(mavsdk point: Mavsdk.Geofence.Point) {
        latitudeDeg = point.latitudeDeg
        longitudeDeg = point.longitudeDeg
    }

    var mavsdkPoint: Mavsdk.Geofence.Point {
        Mavsdk.Geofence.Point(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg)
    }
}
