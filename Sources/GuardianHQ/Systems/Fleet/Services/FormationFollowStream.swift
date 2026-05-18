import Foundation
import Mavsdk
import RxSwift

/// Continuous global-position setpoints for Mission Control **squad convoy** wingmen (PX4 OFFBOARD / ArduPilot Guided).
@MainActor
final class FormationFollowStream {

    struct Target: Equatable, Sendable {
        var coord: RouteCoordinate
        /// Target AMSL altitude for ``Offboard/setPositionGlobal`` / ``Action/gotoLocation``.
        var absoluteAltitudeM: Double
        var yawDeg: Double
        /// When set, streams body-rate pursuit (ArduPilot GUIDED OFFBOARD, or PX4 rover throttle+steering).
        var pursuitForwardMS: Float?
        var pursuitYawspeedDegS: Float?
        /// Catalogue flag: reverse / 3-point moves need body-rate pursuit (not position-global only).
        var useVelocityBodyPursuit: Bool = false
    }

    private enum PursuitPrimeKind: Equatable {
        case positionGlobal
        case offboardBodyVelocity
        case px4GroundThrottleSteering
    }

    private let drone: Drone
    private let stack: FleetAutopilotStack
    private let universalClass: UniversalVehicleClass
    private let profile: ManualControlStepProfile
    private let requestPx4ManualMode: (@MainActor () async -> Void)?
    private let awaitCompletable: @MainActor (Completable) async throws -> Void
    private let log: (String) -> Void

    private var target: Target
    private var streamTask: Task<Void, Never>?
    private(set) var isRunning = false
    private var offboardVelocityPrimed = false
    private var px4RoverActuator: Px4GroundRoverMotionActuator?
    private var px4ManualPrimed = false
    private var primedPursuitKind: PursuitPrimeKind?
    private var consecutiveSetpointFailures = 0
    private let maxConsecutiveSetpointFailures = 12

    init(
        drone: Drone,
        stack: FleetAutopilotStack,
        universalClass: UniversalVehicleClass,
        profile: ManualControlStepProfile,
        initialTarget: Target,
        requestPx4ManualMode: (@MainActor () async -> Void)? = nil,
        awaitCompletable: @escaping @MainActor (Completable) async throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.drone = drone
        self.stack = stack
        self.universalClass = universalClass
        self.profile = profile
        self.target = initialTarget
        self.requestPx4ManualMode = requestPx4ManualMode
        self.awaitCompletable = awaitCompletable
        self.log = log
        if GuardianVehicleMotionActuatorRouting.kind(stack: stack, universalClass: universalClass)
            == .px4GroundThrottleSteering {
            px4RoverActuator = Px4GroundRoverMotionActuator(
                drone: drone,
                profile: profile,
                awaitCompletable: awaitCompletable,
                log: log
            )
        }
    }

    func updateTarget(_ next: Target) {
        target = next
    }

    func start() async -> Bool {
        guard streamTask == nil else { return isRunning }
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
        for _ in 0..<250 {
            if isRunning { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled { return false }
        }
        return isRunning
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
        offboardVelocityPrimed = false
        px4ManualPrimed = false
        primedPursuitKind = nil
        if stack == .px4 {
            do {
                try await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
                log("Formation follow: offboard stop acknowledged.")
            } catch {
                log("Formation follow: offboard stop skipped (\(error.localizedDescription)).")
            }
        }
        try? await px4RoverActuator?.pushNeutral()
        do {
            try await awaitCompletable(drone.action.hold())
            log("Formation follow: hold after stream stop.")
        } catch {
            log("Formation follow: hold skipped (\(error.localizedDescription)).")
        }
    }

    private func run() async {
        defer {
            streamTask = nil
            isRunning = false
            offboardVelocityPrimed = false
            px4ManualPrimed = false
            primedPursuitKind = nil
            consecutiveSetpointFailures = 0
        }
        do {
            try await ensurePrimedForCurrentTarget()
            isRunning = true
            log("Formation follow: setpoint stream active (~10 Hz).")
            while !Task.isCancelled {
                do {
                    try await pushCurrentSetpoint()
                    consecutiveSetpointFailures = 0
                } catch {
                    consecutiveSetpointFailures += 1
                    if consecutiveSetpointFailures == 1 {
                        log("Formation follow: setpoint rejected; re-priming (\(error.localizedDescription)).")
                        try await rePrime()
                    } else if consecutiveSetpointFailures >= maxConsecutiveSetpointFailures {
                        throw error
                    }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch is CancellationError {
            log("Formation follow: stream cancelled.")
        } catch {
            log("Formation follow: stream ended (\(error.localizedDescription)).")
        }
    }

    private func rePrime() async throws {
        offboardVelocityPrimed = false
        px4ManualPrimed = false
        primedPursuitKind = nil
        try await ensurePrimedForCurrentTarget()
    }

    private func ensurePrimedForCurrentTarget() async throws {
        let kind = currentPursuitPrimeKind
        if primedPursuitKind == kind {
            switch kind {
            case .offboardBodyVelocity: if offboardVelocityPrimed { return }
            case .px4GroundThrottleSteering: if px4ManualPrimed { return }
            case .positionGlobal: return
            }
        }
        offboardVelocityPrimed = false
        px4ManualPrimed = false
        try await primeForKind(kind)
        primedPursuitKind = kind
    }

    private var currentPursuitPrimeKind: PursuitPrimeKind {
        if usesPx4GroundManualPursuit { return .px4GroundThrottleSteering }
        if usesOffboardBodyVelocityPursuit { return .offboardBodyVelocity }
        if stack == .px4 { return .positionGlobal }
        return .positionGlobal
    }

    private var usesPx4GroundManualPursuit: Bool {
        guard target.pursuitForwardMS != nil, target.useVelocityBodyPursuit else { return false }
        return GuardianVehicleMotionActuatorRouting.kind(stack: stack, universalClass: universalClass)
            == .px4GroundThrottleSteering
    }

    private var usesOffboardBodyVelocityPursuit: Bool {
        guard target.pursuitForwardMS != nil else { return false }
        if usesPx4GroundManualPursuit { return false }
        if stack == .ardupilot { return true }
        if stack == .px4, universalClass == .ugv { return false }
        return stack == .px4 && universalClass != .ugv
    }

    private func primeForKind(_ kind: PursuitPrimeKind) async throws {
        switch kind {
        case .px4GroundThrottleSteering:
            if stack == .px4 {
                try? await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
            }
            await requestPx4ManualMode?()
            try await px4RoverActuator?.prime()
            px4ManualPrimed = true
            log("Formation follow: PX4 throttle+steering pursuit engaged.")
        case .offboardBodyVelocity:
            try await primeVelocityBodyOffboardIfNeeded()
        case .positionGlobal:
            guard stack == .px4 else { return }
            try await primePx4PositionOffboardIfNeeded()
        }
    }

    private func primeVelocityBodyOffboardIfNeeded() async throws {
        guard !offboardVelocityPrimed else { return }
        if stack == .px4 {
            try? await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
        }
        let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
        try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
        try await awaitCompletable(drone.offboard.start())
        offboardVelocityPrimed = true
        log("Formation follow: OFFBOARD body-velocity pursuit engaged.")
    }

    private func primePx4PositionOffboardIfNeeded() async throws {
        try? await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
        let t = target
        let position = Offboard.PositionGlobalYaw(
            latDeg: t.coord.lat,
            lonDeg: t.coord.lon,
            altM: Float(t.absoluteAltitudeM),
            yawDeg: Float(t.yawDeg),
            altitudeType: .amsl
        )
        try await awaitCompletable(drone.offboard.setPositionGlobal(positionGlobalYaw: position))
        try await awaitCompletable(drone.offboard.start())
        offboardVelocityPrimed = false
        log("Formation follow: OFFBOARD position engaged.")
    }

    private func pushCurrentSetpoint() async throws {
        try await ensurePrimedForCurrentTarget()
        let t = target
        if usesPx4GroundManualPursuit, let forward = t.pursuitForwardMS {
            try await px4RoverActuator?.push(
                bodyForwardMS: forward,
                yawspeedDegS: t.pursuitYawspeedDegS ?? 0
            )
            return
        }
        if usesOffboardBodyVelocityPursuit, let forward = t.pursuitForwardMS {
            let velocity = Offboard.VelocityBodyYawspeed(
                forwardMS: forward,
                rightMS: 0,
                downMS: 0,
                yawspeedDegS: t.pursuitYawspeedDegS ?? 0
            )
            try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: velocity))
            return
        }
        if stack == .px4 {
            let position = Offboard.PositionGlobalYaw(
                latDeg: t.coord.lat,
                lonDeg: t.coord.lon,
                altM: Float(t.absoluteAltitudeM),
                yawDeg: Float(t.yawDeg),
                altitudeType: .amsl
            )
            try await awaitCompletable(drone.offboard.setPositionGlobal(positionGlobalYaw: position))
            return
        }
        try await awaitCompletable(
            drone.action.gotoLocation(
                latitudeDeg: t.coord.lat,
                longitudeDeg: t.coord.lon,
                absoluteAltitudeM: t.absoluteAltitudeM,
                yawDeg: t.yawDeg
            )
        )
    }
}
