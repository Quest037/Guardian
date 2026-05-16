import Foundation
import Mavsdk
import RxSwift

/// MAVSDK **offboard** helpers for ``FleetLinkService`` and catalogue
/// ``FleetCommandName/fleetVehicleDoOffboardStop`` (``FleetVehicleCommand/offboardStop``).
///
/// Park / resume flows that intentionally keep offboard streaming across steps should route
/// stop here so recipes and the link service share one implementation. The continue-after-park
/// recipe runs ``offboardStopCompletable`` **before** mode/arm/start so mission mode is not left fighting offboard.
enum OffboardCoordinator {

    private static let horizontalSpeedStopThresholdMS: Double = 0.49
    private static let brakeTickNs: UInt64 = 100_000_000
    private static let stableNeed: Int = 6
    private static let brakeTimeout: Duration = .seconds(45)
    /// Log every Nth ``setVelocityBody`` in the brake loop (plus tick 1) so operators can confirm traffic.
    private static let brakeLoopLogEveryNTicks: Int = 10

    /// Single-shot ``Offboard/stop`` (ends MAVSDK offboard setpoint streaming).
    static func offboardStopCompletable(drone: Drone) -> Completable {
        drone.offboard.stop()
    }

    /// Human-readable line for a brake-loop tick (for vehicle logs).
    static func px4ParkBrakeLoopTickMessage(iteration: Int, horizontalSpeedMS: Double?, stableTicks: Int) -> String {
        let speedStr: String
        if let v = horizontalSpeedMS {
            speedStr = String(format: "%.2f", v)
        } else {
            speedStr = "nil"
        }
        return "OffboardCoordinator: setVelocityBody(zero) tick #\(iteration) horizontal|v|=\(speedStr) m/s stableTicks=\(stableTicks)/\(stableNeed)"
    }

    /// Fixed global pose streamed during PX4 park so heading does not drift under velocity-only OFFBOARD.
    struct Px4ParkPoseHold: Equatable, Sendable {
        let latitudeDeg: Double
        let longitudeDeg: Double
        let absoluteAltitudeM: Float
        let yawDeg: Float
    }

    /// Seeds zero velocity, ``Offboard/start``, then pushes zero ``setVelocityBody`` until horizontal speed is low (debounced) or timeout.
    ///
    /// When ``poseHold`` is set, each tick also streams ``Offboard/setPositionGlobal`` at the snapshot
    /// lat/lon/alt/yaw captured when park began (PX4 rover OFFBOARD otherwise slews heading arbitrarily).
    ///
    /// - Parameters:
    ///   - awaitCompletable: Bridge to ``FleetLinkService/awaitCompletableForManualStream`` (or equivalent).
    ///   - horizontalGroundSpeedMS: Hub N–E horizontal speed (m/s), or `nil` if unknown.
    ///   - poseHold: Optional pose captured at park command entry.
    ///   - appendDiagnostic: Lines are prefixed by the caller (e.g. `"Park: …"`).
    @MainActor
    static func runPx4ParkZeroVelocityBrakeLoop(
        drone: Drone,
        awaitCompletable: @MainActor (Completable) async throws -> Void,
        horizontalGroundSpeedMS: @MainActor () -> Double?,
        poseHold: Px4ParkPoseHold? = nil,
        appendDiagnostic: @MainActor (String) -> Void
    ) async throws {
        let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
        if let poseHold {
            let position = Offboard.PositionGlobalYaw(
                latDeg: poseHold.latitudeDeg,
                lonDeg: poseHold.longitudeDeg,
                altM: poseHold.absoluteAltitudeM,
                yawDeg: poseHold.yawDeg,
                altitudeType: .amsl
            )
            try await awaitCompletable(drone.offboard.setPositionGlobal(positionGlobalYaw: position))
            appendDiagnostic(
                String(
                    format: "OffboardCoordinator: seed setPositionGlobal hold (yaw=%.1f°) before brake loop.",
                    poseHold.yawDeg
                )
            )
        }
        try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
        appendDiagnostic("OffboardCoordinator: seed setVelocityBody(zero) before Offboard.start.")
        try await awaitCompletable(drone.offboard.start())
        appendDiagnostic("OffboardCoordinator: Offboard.start acknowledged; entering zero-velocity brake loop.")

        let clock = ContinuousClock()
        let brakeStart = clock.now
        var stableTicks = 0
        var iteration = 0
        while true {
            iteration += 1
            if let poseHold {
                let position = Offboard.PositionGlobalYaw(
                    latDeg: poseHold.latitudeDeg,
                    lonDeg: poseHold.longitudeDeg,
                    altM: poseHold.absoluteAltitudeM,
                    yawDeg: poseHold.yawDeg,
                    altitudeType: .amsl
                )
                try await awaitCompletable(drone.offboard.setPositionGlobal(positionGlobalYaw: position))
            }
            try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))

            if let speed = horizontalGroundSpeedMS(), speed < horizontalSpeedStopThresholdMS {
                stableTicks += 1
                if stableTicks >= stableNeed {
                    appendDiagnostic(
                        "OffboardCoordinator: brake complete — \(Self.px4ParkBrakeLoopTickMessage(iteration: iteration, horizontalSpeedMS: speed, stableTicks: stableTicks))."
                    )
                    break
                }
            } else {
                stableTicks = 0
            }

            if iteration == 1 || iteration % Self.brakeLoopLogEveryNTicks == 0 {
                appendDiagnostic(Self.px4ParkBrakeLoopTickMessage(
                    iteration: iteration,
                    horizontalSpeedMS: horizontalGroundSpeedMS(),
                    stableTicks: stableTicks
                ))
            }

            if clock.now - brakeStart >= brakeTimeout {
                appendDiagnostic(
                    "OffboardCoordinator: brake timeout after \(iteration) setVelocityBody ticks (offboard left active)."
                )
                break
            }
            try await Task.sleep(nanoseconds: brakeTickNs)
        }
    }
}
