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
        /// When set, streams ``Offboard/setVelocityBody`` (ArduPilot GUIDED + PX4 OFFBOARD) for gap closure.
        var pursuitForwardMS: Float?
        var pursuitYawspeedDegS: Float?
    }

    private let drone: Drone
    private let stack: FleetAutopilotStack
    /// When `.ugv` on PX4, body velocity is ignored — position-global pursuit only.
    private let universalClass: UniversalVehicleClass
    private let awaitCompletable: @MainActor (Completable) async throws -> Void
    private let log: (String) -> Void

    private var target: Target
    private var streamTask: Task<Void, Never>?
    private(set) var isRunning = false
    private var velocityBodyPrimed = false
    /// Transient PX4 rejections (e.g. mode lag when the primary starts AUTO) before tearing down the stream.
    private var consecutiveSetpointFailures = 0
    private let maxConsecutiveSetpointFailures = 12

    init(
        drone: Drone,
        stack: FleetAutopilotStack,
        universalClass: UniversalVehicleClass,
        initialTarget: Target,
        awaitCompletable: @escaping @MainActor (Completable) async throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.drone = drone
        self.stack = stack
        self.universalClass = universalClass
        self.target = initialTarget
        self.awaitCompletable = awaitCompletable
        self.log = log
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
        for _ in 0..<150 {
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
        velocityBodyPrimed = false
        if stack == .px4 {
            do {
                try await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
                log("Formation follow: offboard stop acknowledged.")
            } catch {
                log("Formation follow: offboard stop skipped (\(error.localizedDescription)).")
            }
        }
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
            velocityBodyPrimed = false
            consecutiveSetpointFailures = 0
        }
        do {
            try await primeOffboardIfNeeded()
            isRunning = true
            log("Formation follow: setpoint stream active (~10 Hz).")
            while !Task.isCancelled {
                do {
                    try await pushCurrentSetpoint()
                    consecutiveSetpointFailures = 0
                } catch {
                    consecutiveSetpointFailures += 1
                    if consecutiveSetpointFailures == 1 {
                        log("Formation follow: setpoint rejected; re-priming OFFBOARD (\(error.localizedDescription)).")
                        try await rePrimeOffboard()
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

    private func rePrimeOffboard() async throws {
        velocityBodyPrimed = false
        try await primeOffboardIfNeeded()
    }

    private var usesVelocityBodyPursuit: Bool {
        guard target.pursuitForwardMS != nil else { return false }
        if stack == .ardupilot { return true }
        return stack == .px4 && universalClass != .ugv
    }

    private func primeOffboardIfNeeded() async throws {
        if usesVelocityBodyPursuit {
            try await primeVelocityBodyOffboardIfNeeded()
            return
        }
        guard stack == .px4 else { return }
        try await primePx4PositionOffboardIfNeeded()
    }

    private func primeVelocityBodyOffboardIfNeeded() async throws {
        guard !velocityBodyPrimed else { return }
        if stack == .px4 {
            do {
                try await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
            } catch {
                log("Formation follow: pre-stream offboard stop skipped.")
            }
        }
        let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
        try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
        try await awaitCompletable(drone.offboard.start())
        velocityBodyPrimed = true
        log("Formation follow: OFFBOARD velocity pursuit engaged.")
    }

    private func primePx4PositionOffboardIfNeeded() async throws {
        do {
            try await awaitCompletable(OffboardCoordinator.offboardStopCompletable(drone: drone))
        } catch {
            log("Formation follow: pre-stream offboard stop skipped.")
        }
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
        log("Formation follow: OFFBOARD position engaged.")
    }

    private func pushCurrentSetpoint() async throws {
        let t = target
        if usesVelocityBodyPursuit, let forward = t.pursuitForwardMS {
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
