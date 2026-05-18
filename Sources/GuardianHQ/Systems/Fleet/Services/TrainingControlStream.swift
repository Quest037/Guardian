import Foundation
import Mavsdk
import RxSwift

/// Open-loop training segments — routes to stack/class actuators (PX4 rover throttle+steering vs OFFBOARD body velocity).
@MainActor
final class TrainingControlStream {

    private let drone: Drone
    private let stack: FleetAutopilotStack
    private let actuatorKind: GuardianVehicleMotionActuatorKind
    private let profile: ManualControlStepProfile
    private let awaitCompletable: @MainActor (Completable) async throws -> Void
    private let log: (String) -> Void

    private var px4RoverActuator: Px4GroundRoverMotionActuator?
    private var offboardPrimed = false
    private(set) var isRunning = false

    init(
        drone: Drone,
        stack: FleetAutopilotStack,
        universalClass: UniversalVehicleClass,
        profile: ManualControlStepProfile,
        awaitCompletable: @escaping @MainActor (Completable) async throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.drone = drone
        self.stack = stack
        self.actuatorKind = GuardianVehicleMotionActuatorRouting.kind(
            stack: stack,
            universalClass: universalClass
        )
        self.profile = profile
        self.awaitCompletable = awaitCompletable
        self.log = log
        if actuatorKind == .px4GroundThrottleSteering {
            px4RoverActuator = Px4GroundRoverMotionActuator(
                drone: drone,
                profile: profile,
                awaitCompletable: awaitCompletable,
                log: log
            )
        }
    }

    func start() async -> Bool {
        do {
            try await primeIfNeeded()
            isRunning = true
            return true
        } catch {
            log("Training control: prime failed (\(error.localizedDescription)).")
            return false
        }
    }

    func stop() async {
        isRunning = false
        offboardPrimed = false
        switch actuatorKind {
        case .offboardBodyVelocity:
            if stack == .px4 {
                try? await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
            }
            let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
            try? await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
        case .px4GroundThrottleSteering:
            if let px4RoverActuator {
                try? await px4RoverActuator.pushNeutral()
                px4RoverActuator.resetPrimeState()
            }
        }
        try? await awaitCompletable(drone.action.hold())
        log("Training control: stopped (\(actuatorKind)).")
    }

    func executeSegment(_ segment: TrainingControlSegment) async throws {
        guard isRunning else { throw TrainingControlStreamError.notRunning }
        try await primeIfNeeded()
        log(
            String(
                format: "Training control: segment fwd %.2f yaw %.0f°/s for %.1fs (%@).",
                segment.bodyForwardMS,
                segment.yawspeedDegS,
                segment.durationS,
                actuatorLabel
            )
        )
        let tickNs: UInt64 = 100_000_000
        let ticks = max(1, Int(ceil(segment.durationS / 0.1)))
        for _ in 0..<ticks {
            try Task.checkCancellation()
            try await push(segment)
            try await Task.sleep(nanoseconds: tickNs)
        }
        try await pushHold()
    }

    private var actuatorLabel: String {
        switch actuatorKind {
        case .offboardBodyVelocity: return "OFFBOARD body velocity"
        case .px4GroundThrottleSteering: return "PX4 throttle+steering"
        }
    }

    private func primeIfNeeded() async throws {
        switch actuatorKind {
        case .offboardBodyVelocity:
            guard !offboardPrimed else { return }
            if stack == .px4 {
                try? await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
            }
            let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
            try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
            try await awaitCompletable(drone.offboard.start())
            offboardPrimed = true
            log("Training control: OFFBOARD body-velocity active (\(stack.displayName)).")
        case .px4GroundThrottleSteering:
            try await px4RoverActuator?.prime()
        }
    }

    private func pushHold() async throws {
        switch actuatorKind {
        case .offboardBodyVelocity:
            let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
            try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
        case .px4GroundThrottleSteering:
            try await px4RoverActuator?.pushNeutral()
        }
    }

    private func push(_ segment: TrainingControlSegment) async throws {
        switch actuatorKind {
        case .offboardBodyVelocity:
            let velocity = Offboard.VelocityBodyYawspeed(
                forwardMS: segment.bodyForwardMS,
                rightMS: segment.bodyRightMS,
                downMS: -segment.climbRateMS,
                yawspeedDegS: segment.yawspeedDegS
            )
            try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: velocity))
        case .px4GroundThrottleSteering:
            try await px4RoverActuator?.push(
                bodyForwardMS: segment.bodyForwardMS,
                yawspeedDegS: segment.yawspeedDegS
            )
        }
    }
}

enum TrainingControlStreamError: Error {
    case notRunning
}
