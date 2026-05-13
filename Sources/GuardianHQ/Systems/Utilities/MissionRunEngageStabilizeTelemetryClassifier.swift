import Foundation

/// Outcome of ``MissionRunEngageStabilizeTelemetryClassifier/evaluate`` for MC-R **Engage Live Drive** stabilize watch.
enum MissionRunEngageStabilizeTelemetryVerdict: Equatable, Sendable {
    /// Hub looks healthy and the chosen stabilize intent appears satisfied.
    case stable
    /// Hub is updating but criteria are not met yet (land-in-progress, mode change, motion settling).
    case pending(reason: String)
    /// Missing hub, stale snapshot, blocked flight mode, or other state the operator should fix before retrying.
    case fault(reason: String)
}

/// Shared hub snapshot checks after operator **Park** / **Loiter** (Engage flow — see ``README.md`` Live Drive / MC-R Engage).
///
/// **Park** “on deck” heuristics align with ``FleetLinkService``’s private park wait (`hubShowsUAVOnDeckForPark`).
/// **Loiter** accepts hold-like and common position-mode strings; horizontal / vertical rate gates are intentionally loose
/// so slow orbit / stack quirks do not block v1 indefinitely.
enum MissionRunEngageStabilizeTelemetryClassifier {

    /// After this interval the MC-R overlay surfaces a **fault** line unless the snapshot is already ``stable``.
    static let operatorWaitTimeoutSeconds: TimeInterval = 90

    private static let blockedFlightModeSubstrings = ["TERMINAT", "FAILSAFE", "EMERGENCY", "CRASH"]

    /// - Parameters:
    ///   - kind: Which stabilize command the operator issued.
    ///   - hub: Latest ``FleetLinkService/hubTelemetryByVehicleID`` snapshot (or primary hub when single-stream).
    ///   - operational: Same-``now`` ``FleetVehicleOperationalModel`` built from that hub (and optional lifecycle).
    ///   - now: Reference clock for freshness and movement summary.
    ///   - maxHubAgeSeconds: Use ``MissionControlReserveSwapInPreflightGates`` live vs simulation limits from the caller.
    static func evaluate(
        kind: MissionRunEngageStabilizeDispatchKind,
        hub: FleetHubVehicleTelemetry?,
        operational: FleetVehicleOperationalModel,
        now: Date,
        maxHubAgeSeconds: TimeInterval
    ) -> MissionRunEngageStabilizeTelemetryVerdict {
        guard let hub else {
            return .fault(reason: "No hub telemetry for this vehicle.")
        }

        let age = now.timeIntervalSince(hub.lastUpdate)
        if age.isFinite, age > maxHubAgeSeconds {
            let secs = Int(round(age))
            let lim = Int(round(maxHubAgeSeconds))
            return .fault(reason: "Telemetry is stale (last hub update \(secs)s ago, limit \(lim)s).")
        }

        let modeUpper = hub.flightMode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !modeUpper.isEmpty, modeUpper != "—" {
            if blockedFlightModeSubstrings.contains(where: { modeUpper.contains($0) }) {
                return .fault(reason: "Flight mode looks like a failsafe or termination state (\(hub.flightMode)).")
            }
        }

        switch kind {
        case .park:
            return evaluatePark(hub: hub, operational: operational)
        case .loiter:
            return evaluateLoiter(hub: hub, operational: operational)
        }
    }

    // MARK: - Park

    /// Same signal shape as ``FleetLinkService`` park wait (`hubShowsUAVOnDeckForPark`).
    private static func hubShowsOnDeckForEngagePark(_ hub: FleetHubVehicleTelemetry) -> Bool {
        if let landed = hub.landedState {
            let norm = landed.lowercased().replacingOccurrences(of: " ", with: "")
            if norm.contains("on_ground") || norm.contains("onground") {
                return true
            }
        }
        if hub.inAir == false { return true }
        if hub.isArmed == false { return true }
        if let rel = hub.relativeAltM, rel.isFinite, rel < 1.5 { return true }
        return false
    }

    private static func evaluatePark(
        hub: FleetHubVehicleTelemetry,
        operational: FleetVehicleOperationalModel
    ) -> MissionRunEngageStabilizeTelemetryVerdict {
        let onDeck = hubShowsOnDeckForEngagePark(hub)
        if !onDeck {
            return .pending(reason: "Waiting for landed, disarmed, or low relative height.")
        }
        if operational.movement.isMovingForOperatorChip {
            return .pending(reason: "Waiting for horizontal motion to settle.")
        }
        return .stable
    }

    // MARK: - Loiter

    private static func evaluateLoiter(
        hub: FleetHubVehicleTelemetry,
        operational: FleetVehicleOperationalModel
    ) -> MissionRunEngageStabilizeTelemetryVerdict {
        let humanized = FleetVehicleLiveStatusBadgeRow.humanizedFlightMode(from: hub)
        let raw = hub.flightMode
        let loiterLike = FleetVehicleLiveStatusBadgeRow.isEngageLoiterLikeFlightMode(
            humanized: humanized,
            rawFlightMode: raw
        )
        if !loiterLike {
            return .pending(reason: "Waiting for hold, loiter, or position-style flight mode.")
        }

        if let vd = hub.velocityDownMS, vd.isFinite, abs(vd) > 0.85 {
            return .pending(reason: "Waiting for vertical rate to settle.")
        }

        if let h = operational.movement.horizontalSpeedMS, h.isFinite, h > 5.5 {
            return .pending(reason: "Waiting for horizontal speed to settle.")
        }

        return .stable
    }

    // MARK: - Live Drive (mission session start)

    /// Narrow probe gate for **Live Drive → Start session** while the vehicle is still bound to a Mission Control run (HandOff §3).
    ///
    /// §1 class rules: **UGV / USV / UUV** require **park** telemetry stable; **UAV** accepts **loiter** *or* **park** stable.
    /// **Unknown** class tries park first, then loiter (same as ``evaluate`` ordering for conservative UX).
    static func evaluateLiveDriveMissionStartStabilizeGate(
        vehicleClass: UniversalVehicleClass,
        hub: FleetHubVehicleTelemetry?,
        operational: FleetVehicleOperationalModel,
        now: Date,
        maxHubAgeSeconds: TimeInterval
    ) -> MissionRunEngageStabilizeTelemetryVerdict {
        switch vehicleClass {
        case .ugv, .usv, .uuv:
            return evaluate(
                kind: .park,
                hub: hub,
                operational: operational,
                now: now,
                maxHubAgeSeconds: maxHubAgeSeconds
            )
        case .uav:
            let loiterV = evaluate(
                kind: .loiter,
                hub: hub,
                operational: operational,
                now: now,
                maxHubAgeSeconds: maxHubAgeSeconds
            )
            if case .stable = loiterV { return loiterV }
            let parkV = evaluate(
                kind: .park,
                hub: hub,
                operational: operational,
                now: now,
                maxHubAgeSeconds: maxHubAgeSeconds
            )
            if case .stable = parkV { return parkV }
            switch (loiterV, parkV) {
            case (.fault(let a), .fault(let b)):
                return .fault(reason: "\(a) Checked park as well: \(b)")
            case (.fault(let a), _):
                return .fault(reason: a)
            case (_, .fault(let b)):
                return .fault(reason: b)
            case (.pending(let a), .pending(let b)):
                return .pending(reason: "Loiter/hold: \(a) Park: \(b)")
            case (.pending(let a), _):
                return .pending(reason: a)
            case (_, .pending(let b)):
                return .pending(reason: b)
            default:
                return parkV
            }
        case .unknown:
            let parkV = evaluate(
                kind: .park,
                hub: hub,
                operational: operational,
                now: now,
                maxHubAgeSeconds: maxHubAgeSeconds
            )
            if case .stable = parkV { return parkV }
            return evaluate(
                kind: .loiter,
                hub: hub,
                operational: operational,
                now: now,
                maxHubAgeSeconds: maxHubAgeSeconds
            )
        }
    }
}
