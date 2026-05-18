import Foundation
import Mavsdk
import RxSwift

/// PX4 rover keyboard-equivalent OFFBOARD substitute: MANUAL-mode throttle + steering via MAVLink.
///
/// Semantically maps to PX4 ``RoverThrottleSetpoint`` + ``RoverSteeringSetpoint`` (signed body-X speed /
/// normalized steering). MAVSDK does not expose those UORB topics yet; Live Drive uses the same
/// ``ManualControl`` wire encoding (see ``ManualControlStream/pushPX4GroundManualSetpoint``).
@MainActor
final class Px4GroundRoverMotionActuator {
    private let drone: Drone
    private let profile: ManualControlStepProfile
    private let awaitCompletable: @MainActor (Completable) async throws -> Void
    private let log: (String) -> Void

    private(set) var isPrimed = false

    init(
        drone: Drone,
        profile: ManualControlStepProfile,
        awaitCompletable: @escaping @MainActor (Completable) async throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.drone = drone
        self.profile = profile
        self.awaitCompletable = awaitCompletable
        self.log = log
    }

    func prime() async throws {
        guard !isPrimed else { return }
        try await pushNormalized(forward: 0, yawRate: 0)
        isPrimed = true
        log("PX4 rover motion: MANUAL_CONTROL throttle/steering primed (neutral).")
    }

    func push(bodyForwardMS: Float, yawspeedDegS: Float) async throws {
        let forwardNorm = Double(bodyForwardMS) / max(profile.maxForwardMS, 0.05)
        let yawNorm = Double(yawspeedDegS) / max(profile.maxYawRateDegS, 1)
        try await pushNormalized(
            forward: clamp(forwardNorm),
            yawRate: clamp(yawNorm)
        )
    }

    func pushNeutral() async throws {
        try await pushNormalized(forward: 0, yawRate: 0)
    }

    func resetPrimeState() {
        isPrimed = false
    }

    private func pushNormalized(forward: Double, yawRate: Double) async throws {
        let throttle01 = 0.5 + 0.5 * forward
        let steering = yawRate
        try await awaitCompletable(
            drone.manualControl.setManualControlInput(
                x: 0,
                y: Float(steering),
                z: Float(throttle01),
                r: Float(steering)
            )
        )
    }

    private func clamp(_ v: Double) -> Double {
        max(-1, min(1, v))
    }
}
