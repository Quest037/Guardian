import Foundation

/// Debug telemetry trace for the formations playground — position/yaw vs slot targets for post-run analysis.
enum FormationsPlaygroundTelemetryEventKind: String, Codable, Sendable, Equatable {
    case sessionStart
    case change
    case sessionEnd
}

struct FormationsPlaygroundTelemetrySample: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: FormationsPlaygroundTelemetryEventKind
    let vehicleLabel: String
    let vehicleID: String?
    let latitudeDeg: Double?
    let longitudeDeg: Double?
    let bodyYawDeg: Double?
    let courseHeadingDeg: Double?
    let slotLatitudeDeg: Double
    let slotLongitudeDeg: Double
    let desiredHeadingDeg: Double
    let primaryLatitudeDeg: Double
    let primaryLongitudeDeg: Double
    let primaryHeadingDeg: Double
    let distanceToSlotM: Double?
    let alongErrorM: Double?
    let signedLateralErrorM: Double?
    let headingErrorDeg: Double?
    let movementID: String?
    let bodyForwardMS: Double?
    let yawspeedDegS: Double?
    let streamPositionYawHold: Bool
    let positionWithinSlot: Bool
    let headingAligned: Bool
    let deltaEastFromStartM: Double?
    let deltaNorthFromStartM: Double?
    let deltaHeadingFromStartDeg: Double?
}

/// Inputs from the playground tick loop (keeps the recorder testable without fleet services).
struct FormationsPlaygroundTelemetryRecordInput: Equatable, Sendable {
    let slotID: UUID
    let vehicleLabel: String
    let vehicleID: String?
    let hub: FleetHubVehicleTelemetry?
    let slot: RouteCoordinate
    let targetHeadingDeg: Double
    let primaryLatitudeDeg: Double
    let primaryLongitudeDeg: Double
    let primaryHeadingDeg: Double
    let movementID: GuardianMovementID?
    let bodyForwardMS: Double?
    let yawspeedDegS: Double?
    let streamPositionYawHold: Bool
    let arrivalM: Double
    let headingToleranceDeg: Double
}

struct FormationsPlaygroundTelemetrySessionInfo: Equatable, Sendable {
    let sessionID: UUID
    let startedAt: Date
    let formationTitle: String
    let shapeTitle: String
    let vehicleClassTitle: String
}

/// Records position/heading changes vs formation slot targets; export for MRE tuning analysis.
struct FormationsPlaygroundTelemetryTraceRecorder: Sendable {
    private(set) var session: FormationsPlaygroundTelemetrySessionInfo?
    private(set) var samples: [FormationsPlaygroundTelemetrySample] = []

    private var baselineBySlotID: [UUID: (lat: Double, lon: Double, yaw: Double?)] = [:]
    private var lastSignatureBySlotID: [UUID: String] = [:]

    private static let maxSamples = 2_000
    private static let positionChangeM = 0.3
    private static let headingChangeDeg = 2.0
    private static let slotChangeM = 0.15
    private static let targetHeadingChangeDeg = 1.0

    mutating func clear() {
        session = nil
        samples = []
        baselineBySlotID = [:]
        lastSignatureBySlotID = [:]
    }

    mutating func beginSession(
        formationTitle: String,
        shapeTitle: String,
        vehicleClassTitle: String,
        startedAt: Date = Date()
    ) {
        clear()
        session = FormationsPlaygroundTelemetrySessionInfo(
            sessionID: UUID(),
            startedAt: startedAt,
            formationTitle: formationTitle,
            shapeTitle: shapeTitle,
            vehicleClassTitle: vehicleClassTitle
        )
    }

    mutating func endSession(endedAt: Date = Date()) {
        guard session != nil else { return }
        append(
            makeSample(
                kind: .sessionEnd,
                timestamp: endedAt,
                input: nil,
                vehicleLabel: "Squad",
                vehicleID: nil,
                slot: RouteCoordinate(),
                targetHeadingDeg: 0,
                primaryLat: 0,
                primaryLon: 0,
                primaryHeadingDeg: 0,
                metrics: nil,
                movementID: nil,
                bodyForwardMS: nil,
                yawspeedDegS: nil,
                streamPositionYawHold: false,
                arrivalM: 0,
                headingToleranceDeg: 0
            )
        )
    }

    mutating func record(_ input: FormationsPlaygroundTelemetryRecordInput) {
        guard session != nil else { return }
        let metrics = Self.metrics(for: input)
        let signature = Self.signature(input: input, metrics: metrics)

        if baselineBySlotID[input.slotID] == nil {
            if let metrics {
                baselineBySlotID[input.slotID] = (metrics.lat, metrics.lon, metrics.bodyYaw)
            }
            appendSessionStart(input: input, metrics: metrics)
            lastSignatureBySlotID[input.slotID] = signature
            return
        }

        guard lastSignatureBySlotID[input.slotID] != signature else { return }
        lastSignatureBySlotID[input.slotID] = signature
        append(
            makeSample(
                kind: .change,
                timestamp: Date(),
                input: input,
                vehicleLabel: input.vehicleLabel,
                vehicleID: input.vehicleID,
                slot: input.slot,
                targetHeadingDeg: input.targetHeadingDeg,
                primaryLat: input.primaryLatitudeDeg,
                primaryLon: input.primaryLongitudeDeg,
                primaryHeadingDeg: input.primaryHeadingDeg,
                metrics: metrics,
                movementID: input.movementID?.rawValue,
                bodyForwardMS: input.bodyForwardMS,
                yawspeedDegS: input.yawspeedDegS,
                streamPositionYawHold: input.streamPositionYawHold,
                arrivalM: input.arrivalM,
                headingToleranceDeg: input.headingToleranceDeg
            )
        )
    }

    // MARK: - Export

    func plainTextExport() -> String {
        guard let session else { return "" }
        let formatter = Self.timestampFormatter
        var lines: [String] = [
            "# Guardian Formations telemetry trace",
            "session_id: \(session.sessionID.uuidString)",
            "started: \(formatter.string(from: session.startedAt))",
            "formation: \(session.formationTitle)",
            "spacing: \(session.shapeTitle)",
            "vehicle_class: \(session.vehicleClassTitle)",
            "sample_count: \(samples.count)",
            "",
        ]

        let grouped = Dictionary(grouping: samples.filter { $0.vehicleLabel != "Squad" }) { $0.vehicleLabel }
        let labels = grouped.keys.sorted { lhs, rhs in
            if lhs == "Primary" { return true }
            if rhs == "Primary" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        for label in labels {
            guard let rows = grouped[label]?.sorted(by: { $0.timestamp < $1.timestamp }) else { continue }
            lines.append("## \(label)")
            if let vid = rows.first?.vehicleID {
                lines.append("vehicle_id: \(vid)")
            }
            for row in rows {
                lines.append(Self.plainTextLine(row, formatter: formatter))
            }
            if let last = rows.last(where: { $0.kind == .change || $0.kind == .sessionStart }),
               let dist = last.distanceToSlotM,
               let hdgErr = last.headingErrorDeg {
                let assembled = last.positionWithinSlot && last.headingAligned
                lines.append(
                    String(
                        format: "outcome: %@ (dist %.2f m, heading err %.1f°, pos %@, hdg %@)",
                        assembled ? "ASSEMBLED" : "NOT_ASSEMBLED",
                        dist,
                        abs(hdgErr),
                        last.positionWithinSlot ? "ok" : "off",
                        last.headingAligned ? "ok" : "off"
                    )
                )
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func jsonLinesExport() -> String {
        guard let session else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var lines: [String] = []
        if let header = try? encoder.encode(
            FormationsPlaygroundTelemetryJSONHeader(
                sessionID: session.sessionID,
                startedAt: session.startedAt,
                formation: session.formationTitle,
                shape: session.shapeTitle,
                vehicleClass: session.vehicleClassTitle
            )
        ), let s = String(data: header, encoding: .utf8) {
            lines.append(s)
        }
        for sample in samples {
            let row = FormationsPlaygroundTelemetryJSONLine.from(sample)
            if let data = try? encoder.encode(row), let s = String(data: data, encoding: .utf8) {
                lines.append(s)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private struct ResolvedMetrics {
        let lat: Double
        let lon: Double
        let bodyYaw: Double?
        let courseHeading: Double?
        let distM: Double
        let alongM: Double
        let lateralM: Double
        let headingErr: Double?
        let positionOk: Bool
        let headingOk: Bool
    }

    private mutating func appendSessionStart(
        input: FormationsPlaygroundTelemetryRecordInput,
        metrics: ResolvedMetrics?
    ) {
        append(
            makeSample(
                kind: .sessionStart,
                timestamp: Date(),
                input: input,
                vehicleLabel: input.vehicleLabel,
                vehicleID: input.vehicleID,
                slot: input.slot,
                targetHeadingDeg: input.targetHeadingDeg,
                primaryLat: input.primaryLatitudeDeg,
                primaryLon: input.primaryLongitudeDeg,
                primaryHeadingDeg: input.primaryHeadingDeg,
                metrics: metrics,
                movementID: input.movementID?.rawValue,
                bodyForwardMS: input.bodyForwardMS,
                yawspeedDegS: input.yawspeedDegS,
                streamPositionYawHold: input.streamPositionYawHold,
                arrivalM: input.arrivalM,
                headingToleranceDeg: input.headingToleranceDeg
            )
        )
    }

    private mutating func append(_ sample: FormationsPlaygroundTelemetrySample) {
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }

    private func makeSample(
        kind: FormationsPlaygroundTelemetryEventKind,
        timestamp: Date,
        input: FormationsPlaygroundTelemetryRecordInput?,
        vehicleLabel: String,
        vehicleID: String?,
        slot: RouteCoordinate,
        targetHeadingDeg: Double,
        primaryLat: Double,
        primaryLon: Double,
        primaryHeadingDeg: Double,
        metrics: ResolvedMetrics?,
        movementID: String?,
        bodyForwardMS: Double?,
        yawspeedDegS: Double?,
        streamPositionYawHold: Bool,
        arrivalM: Double,
        headingToleranceDeg: Double
    ) -> FormationsPlaygroundTelemetrySample {
        let baseline = input.flatMap { baselineBySlotID[$0.slotID] }
        var deltaE: Double?
        var deltaN: Double?
        var deltaH: Double?
        if let metrics, let baseline {
            let latRad = baseline.lat * .pi / 180
            let mPerLon = MissionControlSquadConvoyFormationUtilities.metresPerDegreeLatitude
                * max(0.01, cos(latRad))
            deltaE = (metrics.lon - baseline.lon) * mPerLon
            deltaN = (metrics.lat - baseline.lat) * MissionControlSquadConvoyFormationUtilities.metresPerDegreeLatitude
            if let yaw = metrics.bodyYaw, let baseYaw = baseline.yaw {
                deltaH = MissionTelemetryGeo.angleDifferenceDeg(yaw, baseYaw)
            }
        }

        return FormationsPlaygroundTelemetrySample(
            id: UUID(),
            timestamp: timestamp,
            kind: kind,
            vehicleLabel: vehicleLabel,
            vehicleID: vehicleID,
            latitudeDeg: metrics?.lat,
            longitudeDeg: metrics?.lon,
            bodyYawDeg: metrics?.bodyYaw,
            courseHeadingDeg: metrics?.courseHeading,
            slotLatitudeDeg: slot.lat,
            slotLongitudeDeg: slot.lon,
            desiredHeadingDeg: targetHeadingDeg,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: primaryLon,
            primaryHeadingDeg: primaryHeadingDeg,
            distanceToSlotM: metrics?.distM,
            alongErrorM: metrics?.alongM,
            signedLateralErrorM: metrics?.lateralM,
            headingErrorDeg: metrics?.headingErr,
            movementID: movementID,
            bodyForwardMS: bodyForwardMS,
            yawspeedDegS: yawspeedDegS,
            streamPositionYawHold: streamPositionYawHold,
            positionWithinSlot: metrics?.positionOk ?? false,
            headingAligned: metrics?.headingOk ?? false,
            deltaEastFromStartM: deltaE,
            deltaNorthFromStartM: deltaN,
            deltaHeadingFromStartDeg: deltaH
        )
    }

    private static func metrics(
        for input: FormationsPlaygroundTelemetryRecordInput
    ) -> ResolvedMetrics? {
        guard let hub = input.hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }

        let headingUsed = MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub)
        let distM = MissionRunSquadConvoyAssemblyUtilities.distanceToSlotM(
            wingmanLatitudeDeg: lat,
            wingmanLongitudeDeg: lon,
            slot: input.slot
        )
        let alongM = MissionControlSquadConvoyFormationUtilities.convoyAlongTrackErrorM(
            wingmanLatitudeDeg: lat,
            wingmanLongitudeDeg: lon,
            slotCoordinate: input.slot,
            convoyHeadingDeg: input.targetHeadingDeg
        )
        let lateralM = MissionControlSquadConvoyFormationUtilities.convoySignedLateralErrorM(
            wingmanLatitudeDeg: lat,
            wingmanLongitudeDeg: lon,
            slotCoordinate: input.slot,
            convoyHeadingDeg: input.targetHeadingDeg
        )
        let headingErr = MissionSquadFormationHeadingPolicy.headingErrorDeg(
            hub: hub,
            targetHeadingDeg: input.targetHeadingDeg
        )
        let positionOk = distM <= input.arrivalM
        let headingOk = MissionSquadFormationHeadingPolicy.isHeadingAligned(
            hub: hub,
            targetHeadingDeg: input.targetHeadingDeg,
            toleranceDeg: input.headingToleranceDeg
        )
        return ResolvedMetrics(
            lat: lat,
            lon: lon,
            bodyYaw: headingUsed,
            courseHeading: hub.yawDeg,
            distM: distM,
            alongM: alongM,
            lateralM: lateralM,
            headingErr: headingErr,
            positionOk: positionOk,
            headingOk: headingOk
        )
    }

    private static func signature(
        input: FormationsPlaygroundTelemetryRecordInput,
        metrics: ResolvedMetrics?
    ) -> String {
        guard let metrics else { return "no_telemetry" }
        let posBucket = String(format: "%.4f,%.4f", metrics.lat, metrics.lon)
        let yawBucket = metrics.bodyYaw.map { String(format: "%.0f", $0) } ?? "—"
        let slotBucket = String(format: "%.5f,%.5f", input.slot.lat, input.slot.lon)
        let targetH = String(format: "%.0f", input.targetHeadingDeg)
        let move = input.movementID?.rawValue ?? "—"
        let fwd = input.bodyForwardMS.map { String(format: "%.2f", $0) } ?? "—"
        let yawR = input.yawspeedDegS.map { String(format: "%.1f", $0) } ?? "—"
        let flags = "\(metrics.positionOk)|\(metrics.headingOk)|\(input.streamPositionYawHold)"
        return "\(posBucket)|\(yawBucket)|\(slotBucket)|\(targetH)|\(move)|\(fwd)|\(yawR)|\(flags)"
    }

    private static func plainTextLine(
        _ sample: FormationsPlaygroundTelemetrySample,
        formatter: DateFormatter
    ) -> String {
        let ts = formatter.string(from: sample.timestamp)
        let kind = sample.kind.rawValue
        if sample.kind == .sessionEnd {
            return "[\(ts)] session_end"
        }
        let lat = sample.latitudeDeg.map { String(format: "%.6f", $0) } ?? "—"
        let lon = sample.longitudeDeg.map { String(format: "%.6f", $0) } ?? "—"
        let yaw = sample.bodyYawDeg.map { String(format: "%.0f", $0) } ?? "—"
        let course = sample.courseHeadingDeg.map { String(format: "%.0f", $0) } ?? "—"
        let dist = sample.distanceToSlotM.map { String(format: "%.2f", $0) } ?? "—"
        let hdgErr = sample.headingErrorDeg.map { String(format: "%.1f", abs($0)) } ?? "—"
        let along = sample.alongErrorM.map { String(format: "%.2f", $0) } ?? "—"
        let latErr = sample.signedLateralErrorM.map { String(format: "%.2f", $0) } ?? "—"
        let move = sample.movementID ?? "—"
        let fwd = sample.bodyForwardMS.map { String(format: "%.2f", $0) } ?? "—"
        let yawRate = sample.yawspeedDegS.map { String(format: "%.1f", $0) } ?? "—"
        let slot = String(format: "%.6f,%.6f", sample.slotLatitudeDeg, sample.slotLongitudeDeg)
        let primary = String(format: "%.6f,%.6f hdg %.0f°", sample.primaryLatitudeDeg, sample.primaryLongitudeDeg, sample.primaryHeadingDeg)
        let delta = [
            sample.deltaEastFromStartM.map { String(format: "ΔE %.2f m", $0) },
            sample.deltaNorthFromStartM.map { String(format: "ΔN %.2f m", $0) },
            sample.deltaHeadingFromStartDeg.map { String(format: "Δhdg %.1f°", $0) },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let deltaSuffix = delta.isEmpty ? "" : " \(delta)"
        return """
        [\(ts)] \(kind) pos \(lat),\(lon) heading \(yaw)° yaw \(course)° → slot \(slot) target_hdg \(String(format: "%.0f", sample.desiredHeadingDeg))° primary \(primary) dist \(dist)m along \(along)m lateral \(latErr)m hdg_err \(hdgErr)° move \(move) fwd \(fwd) yaw_rate \(yawRate) stream_pos_yaw \(sample.streamPositionYawHold) pos_ok \(sample.positionWithinSlot) hdg_ok \(sample.headingAligned)\(deltaSuffix)
        """
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - JSONL export rows

private struct FormationsPlaygroundTelemetryJSONHeader: Encodable {
    let type = "session"
    let sessionID: UUID
    let startedAt: Date
    let formation: String
    let shape: String
    let vehicleClass: String

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case startedAt = "started_at"
        case formation
        case shape
        case vehicleClass = "vehicle_class"
    }
}

private struct FormationsPlaygroundTelemetryJSONLine: Encodable {
    let type: String
    let t: Date
    let event: String
    let vehicle: String
    let vehicleID: String?
    let lat: Double?
    let lon: Double?
    let bodyYawDeg: Double?
    let courseHeadingDeg: Double?
    let slotLat: Double
    let slotLon: Double
    let targetHeadingDeg: Double
    let primaryLat: Double
    let primaryLon: Double
    let primaryHeadingDeg: Double
    let distToSlotM: Double?
    let alongErrorM: Double?
    let lateralErrorM: Double?
    let headingErrorDeg: Double?
    let movementID: String?
    let bodyForwardMS: Double?
    let yawspeedDegS: Double?
    let streamPositionYawHold: Bool
    let positionOk: Bool
    let headingOk: Bool
    let deltaEastM: Double?
    let deltaNorthM: Double?
    let deltaHeadingDeg: Double?

    static func from(_ sample: FormationsPlaygroundTelemetrySample) -> Self {
        Self(
            type: "sample",
            t: sample.timestamp,
            event: sample.kind.rawValue,
            vehicle: sample.vehicleLabel,
            vehicleID: sample.vehicleID,
            lat: sample.latitudeDeg,
            lon: sample.longitudeDeg,
            bodyYawDeg: sample.bodyYawDeg,
            courseHeadingDeg: sample.courseHeadingDeg,
            slotLat: sample.slotLatitudeDeg,
            slotLon: sample.slotLongitudeDeg,
            targetHeadingDeg: sample.desiredHeadingDeg,
            primaryLat: sample.primaryLatitudeDeg,
            primaryLon: sample.primaryLongitudeDeg,
            primaryHeadingDeg: sample.primaryHeadingDeg,
            distToSlotM: sample.distanceToSlotM,
            alongErrorM: sample.alongErrorM,
            lateralErrorM: sample.signedLateralErrorM,
            headingErrorDeg: sample.headingErrorDeg,
            movementID: sample.movementID,
            bodyForwardMS: sample.bodyForwardMS,
            yawspeedDegS: sample.yawspeedDegS,
            streamPositionYawHold: sample.streamPositionYawHold,
            positionOk: sample.positionWithinSlot,
            headingOk: sample.headingAligned,
            deltaEastM: sample.deltaEastFromStartM,
            deltaNorthM: sample.deltaNorthFromStartM,
            deltaHeadingDeg: sample.deltaHeadingFromStartDeg
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, t, event, vehicle
        case vehicleID = "vehicle_id"
        case lat, lon
        case bodyYawDeg = "body_yaw_deg"
        case courseHeadingDeg = "course_heading_deg"
        case slotLat = "slot_lat"
        case slotLon = "slot_lon"
        case targetHeadingDeg = "target_heading_deg"
        case primaryLat = "primary_lat"
        case primaryLon = "primary_lon"
        case primaryHeadingDeg = "primary_heading_deg"
        case distToSlotM = "dist_to_slot_m"
        case alongErrorM = "along_error_m"
        case lateralErrorM = "lateral_error_m"
        case headingErrorDeg = "heading_error_deg"
        case movementID = "movement_id"
        case bodyForwardMS = "body_forward_m_s"
        case yawspeedDegS = "yawspeed_deg_s"
        case streamPositionYawHold = "stream_position_yaw_hold"
        case positionOk = "position_ok"
        case headingOk = "heading_ok"
        case deltaEastM = "delta_east_m"
        case deltaNorthM = "delta_north_m"
        case deltaHeadingDeg = "delta_heading_deg"
    }
}
