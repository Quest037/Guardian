import Foundation
import Mavsdk
import RxSwift

/// Continuous body-frame velocity / virtual-stick streamer for one vehicle.
///
/// Why this exists: keyboard and gamepad input are *streams*, not one-shot commands.
/// Sending a fresh `gotoLocation` for every keypress (the previous approach) hits
/// per-stack limits — PX4 and ArduPilot both expect a continuous setpoint at 10 Hz+
/// or they fall back to RC loss / failsafe behaviour.
///
/// `ManualControlStream` owns:
/// - the plugin lifecycle (`Offboard.start()` for the body-velocity mode)
/// - a 30 Hz tick timer that re-pushes the latest setpoint
/// - a clean shutdown that zeroes the setpoint and exits the plugin mode
///
/// Three modes are supported, selected by the caller based on stack + class + input source:
///
/// - `.bodyVelocity` — `Offboard.setVelocityBody(forwardMS, rightMS, downMS, yawspeedDegS)`.
///   The default keyboard primitive. Works for **every** vehicle class on ArduPilot
///   (GUIDED maps body-frame velocity onto TurnRateAndSpeed for rovers/boats and
///   honours it directly for copters/subs) and for PX4 copters / subs. Per ArduPilot's
///   MAVLink rover docs: "Velocity is relative to the vehicle's current heading. Use
///   this to specify the speed forward or backwards (if you use negative values)" —
///   negative `forwardMS` reverses the rover natively without any `GUID_OPTIONS` bit.
///
/// - `.px4GroundManual` — PX4 Rover (Ackermann/Differential/Mecanum) keyboard path.
///   PX4's RoverAckermann OFFBOARD handler does **not** subscribe to body-frame
///   velocity setpoints — it ignores `SET_POSITION_TARGET_LOCAL_NED` for everything
///   except a global position setpoint, so `.bodyVelocity` is silently dropped. The
///   supported control surface is MANUAL mode + a `MANUAL_CONTROL` MAVLink stream.
///   `Shell.send("commander mode manual")` puts the autopilot into MANUAL, then we
///   stream `ManualControl.setManualControlInput(x:0, y:0, z:forward, r:yawRate)` at
///   30 Hz. PX4's `mavlink_receiver.cpp` publishes signed `z` to
///   `manual_control_setpoint.throttle` (-1 = full reverse, +1 = full forward) and
///   the rover module honours it directly. Yaw stick (`r`) drives the steering
///   actuator. MANUAL drops to HOLD if the stream stops for ~0.5 s, so the 30 Hz
///   tick doubles as the heartbeat that keeps the vehicle live.
///
/// - `.manualControl` — `ManualControl.setManualControlInput(x, y, z, r)` with the
///   classic multicopter axis convention (z = collective thrust 0…1, neutral 0.5).
///   Reserved for analog gamepad sticks on holonomic vehicles, where the raw axis
///   position passes through to the autopilot for stack-defined shaping.
@MainActor
final class ManualControlStream {
    enum Mode: Equatable {
        /// `Offboard.setVelocityBody` — body-frame velocity + yaw rate.
        ///
        /// Used for every class on ArduPilot, plus copters/subs on PX4. ArduPilot Rover
        /// GUIDED handles negative `forwardMS` as native reverse; copters and subs are
        /// holonomic in body frame and honour the velocity directly.
        case bodyVelocity

        /// PX4 ground-vehicle keyboard path: switch the autopilot to MANUAL via
        /// `commander mode manual`, then stream `MANUAL_CONTROL` at 30 Hz. PX4's
        /// RoverAckermann OFFBOARD handler ignores body-frame velocity, so `.bodyVelocity`
        /// will not move a PX4 rover — this mode is the only working keyboard primitive
        /// for PX4 UGV/USV. Axis layout: `x=0, y=0, z=forward (signed), r=yawRate`.
        case px4GroundManual

        /// `ManualControl.setManualControlInput` virtual-stick stream with multicopter
        /// axis convention (z = thrust 0…1). Reserved for analog gamepad / joystick input.
        case manualControl
    }

    /// Caller-facing intent. All axes are normalized to `-1.0…1.0`.
    /// - `forward`: +1 forward, -1 backward (body-frame).
    /// - `right`:   +1 right,   -1 left    (body-frame, ignored for non-holonomic vehicles).
    /// - `up`:      +1 ascend,  -1 descend (NEGATED to NED `down` internally).
    /// - `yawRate`: +1 yaw right (clockwise), -1 yaw left.
    struct OperatorIntent: Equatable {
        var forward: Double = 0
        var right: Double = 0
        var up: Double = 0
        var yawRate: Double = 0

        static let zero = OperatorIntent()

        var isZero: Bool {
            forward == 0 && right == 0 && up == 0 && yawRate == 0
        }
    }

    private let vehicleID: String
    private let drone: Drone
    private let stack: FleetAutopilotStack
    private let mode: Mode
    private let log: (String) -> Void

    private(set) var isRunning: Bool = false
    private var startTask: Task<Bool, Never>?

    private var currentIntent: OperatorIntent = .zero

    private var profile: ManualControlStepProfile

    private var timer: Timer?
    private let bag = DisposeBag()

    /// 30 Hz tick — well above PX4's 2 Hz Offboard timeout and ArduPilot's 3 s GUIDED
    /// timeout, while staying inexpensive on the CPU and gRPC pipe.
    private let tickIntervalS: TimeInterval = 1.0 / 30.0

    init(
        vehicleID: String,
        drone: Drone,
        stack: FleetAutopilotStack,
        mode: Mode,
        profile: ManualControlStepProfile,
        log: @escaping (String) -> Void
    ) {
        self.vehicleID = vehicleID
        self.drone = drone
        self.stack = stack
        self.mode = mode
        self.profile = profile
        self.log = log
    }

    func updateProfile(_ profile: ManualControlStepProfile) {
        self.profile = profile
    }

    /// Push a fresh operator intent. Called whenever the held-key set changes
    /// (or every gamepad poll). The timer thread will pick this up on its next tick
    /// and continues re-pushing it until the next `update(intent:)` call — there is no
    /// time-based watchdog because keyboard input is edge-triggered (the held set IS the
    /// source of truth) and the session-end path explicitly stops the stream.
    func update(intent: OperatorIntent) {
        currentIntent = intent
    }

    /// Enter the streaming mode and begin pushing setpoints at 30 Hz.
    /// Returns `true` if the autopilot accepted the mode change.
    @discardableResult
    func start() async -> Bool {
        if isRunning { return true }
        if let task = startTask { return await task.value }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performStart()
        }
        startTask = task
        let result = await task.value
        startTask = nil
        return result
    }

    private func performStart() async -> Bool {
        switch mode {
        case .bodyVelocity:
            // Seed a zero setpoint before calling start() — required by both PX4 and ArduPilot
            // before they'll accept the mode-change request. Skipping this seed is the most
            // common reason `Offboard.start` reports an error in MAVSDK.
            let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
            do {
                try await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
            } catch {
                log("Manual stream: failed to seed Offboard body setpoint: \(error.localizedDescription).")
                return false
            }
            do {
                try await awaitCompletable(drone.offboard.start())
            } catch {
                log("Manual stream: Offboard.start failed (stack=\(stack.displayName)): \(error.localizedDescription).")
                return false
            }
            log("Manual stream: Offboard body-velocity active (stack=\(stack.displayName)).")

        case .px4GroundManual:
            // Seed a neutral MANUAL_CONTROL frame and start the 30 Hz tick. The
            // actual mode transition (`SET_MODE → MANUAL`) is owned by
            // `FleetLinkService.startManualControlStream` because it requires raw
            // MAVLink (`Shell.send("commander mode manual")` is silently dropped by
            // PX4 SITL — see `Px4ModeCommander` for the full diagnosis). The caller
            // sequences: prime stream → 300 ms warm-up → SET_MODE, so the rover
            // module sees a live `manual_control_setpoint` topic before the
            // commander processes the mode-change request.
            //
            // Crucially the seed uses `z = 0.5` — PX4 multicopter throttle convention
            // (see `pushPX4GroundManualSetpoint` for the maths). Sending `z = 0`
            // reads as full reverse and PX4's commander will refuse the MANUAL
            // transition because the seed throttle violates the safety check.
            do {
                try await awaitCompletable(
                    drone.manualControl.setManualControlInput(x: 0, y: 0, z: 0.5, r: 0)
                )
            } catch {
                log("Manual stream: PX4 ManualControl seed failed: \(error.localizedDescription).")
                return false
            }
            log("Manual stream: PX4 ground MANUAL_CONTROL primed.")

        case .manualControl:
            // Seed a neutral MANUAL_CONTROL message so the autopilot has an initial setpoint
            // before the 30 Hz tick takes over. Multicopter convention: z=0.5 is hover.
            // Caller is responsible for switching the autopilot to a mode that accepts
            // MANUAL_CONTROL (POSCTL on PX4 / a stick mode on ArduPilot).
            do {
                try await awaitCompletable(
                    drone.manualControl.setManualControlInput(x: 0, y: 0, z: 0.5, r: 0)
                )
            } catch {
                log("Manual stream: ManualControl seed failed: \(error.localizedDescription).")
                return false
            }
            log("Manual stream: ManualControl (virtual stick) active (stack=\(stack.displayName)).")
        }

        isRunning = true
        scheduleTimer()
        return true
    }

    /// Stop streaming, zero the setpoint, exit the plugin mode and request a hold.
    func stop() async {
        startTask?.cancel()
        startTask = nil

        let wasRunning = isRunning
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentIntent = .zero

        guard wasRunning else { return }

        switch mode {
        case .bodyVelocity:
            let zero = Offboard.VelocityBodyYawspeed(forwardMS: 0, rightMS: 0, downMS: 0, yawspeedDegS: 0)
            _ = try? await awaitCompletable(drone.offboard.setVelocityBody(velocityBodyYawspeed: zero))
            _ = try? await awaitCompletable(drone.offboard.stop())
        case .px4GroundManual:
            // Push a final neutral throttle/steering frame so the rover decelerates to a stop
            // before the timer dies. `z = 0.5` is the PX4 multicopter-throttle midpoint that
            // decodes to `manual_control_setpoint.throttle = 0` — anything else (especially
            // `z = 0`) lands on full reverse on the wire. We deliberately leave the autopilot
            // in MANUAL mode — the session-end menu (`.idle` / `.holdPosition` /
            // `.returnToLaunch`) is responsible for moving the vehicle to whatever
            // post-session mode the operator selected.
            _ = try? await awaitCompletable(
                drone.manualControl.setManualControlInput(x: 0, y: 0, z: 0.5, r: 0)
            )
        case .manualControl:
            _ = try? await awaitCompletable(
                drone.manualControl.setManualControlInput(x: 0, y: 0, z: 0.5, r: 0)
            )
        }

        log("Manual stream: stopped.")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: tickIntervalS, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // `.common` keeps the tick firing during menu tracking and scrolling; we don't want
        // the operator to lose control because they opened the End-Session menu.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isRunning else { return }
        switch mode {
        case .bodyVelocity:
            pushBodyVelocitySetpoint(for: currentIntent)
        case .px4GroundManual:
            pushPX4GroundManualSetpoint(for: currentIntent)
        case .manualControl:
            pushManualControlSetpoint(for: currentIntent)
        }
    }

    private func pushBodyVelocitySetpoint(for intent: OperatorIntent) {
        // NED frame: down is positive, so ascend (+up) is negative downMS.
        //
        // ArduPilot Rover GUIDED interprets this body-frame setpoint as TurnRateAndSpeed
        // submode: `forwardMS` is signed forward speed (negative = reverse, native), and
        // `yawspeedDegS` drives steering rate. The autopilot does NOT synthesize an
        // implicit yaw target from the velocity vector — when forward and yaw are both
        // zero the rover simply stops and holds heading. Copters and subs honour the same
        // setpoint with body-frame velocity + yaw rate.
        //
        // Strafe is wired through but the LiveDrive layer zeros it for UGV/USV via the
        // per-class `ManualControlStepProfile.maxStrafeMS = 0`, so non-holonomic vehicles
        // never see a non-zero `rightMS` even if the operator presses A/D.
        let setpoint = Offboard.VelocityBodyYawspeed(
            forwardMS: Float(clamp(intent.forward) * profile.maxForwardMS),
            rightMS: Float(clamp(intent.right) * profile.maxStrafeMS),
            downMS: Float(-clamp(intent.up) * profile.maxVerticalMS),
            yawspeedDegS: Float(clamp(intent.yawRate) * profile.maxYawRateDegS)
        )
        drone.offboard.setVelocityBody(velocityBodyYawspeed: setpoint)
            .subscribe(onCompleted: {}, onError: { _ in })
            .disposed(by: bag)
    }

    /// PX4 rover MANUAL-mode setpoint.
    ///
    /// Two PX4 quirks force a specific axis mapping that's nothing like the obvious
    /// "forward → z, yaw → r" guess:
    ///
    /// **1. `z` is the multicopter "0…1 thrust" axis, not signed throttle.**
    /// PX4's `mavlink_receiver.cpp` recenters `MANUAL_CONTROL.z` around 0.5 to derive
    /// `manual_control_setpoint.throttle`:
    ///
    ///     throttle = (z/1000 - 0.5) * 2     // line in handle_message_manual_control
    ///
    /// So the wire convention is: `z = 0` ⇒ full reverse, `z = 0.5` ⇒ stop, `z = 1.0`
    /// ⇒ full forward. Sending our signed `intent.forward` directly used to make the
    /// rover idle in reverse (`forward=0` → `z=0` → `throttle=-1`) — exactly the
    /// "drives backwards with no keys pressed" symptom we hit. The remap below puts
    /// us on the same convention QGroundControl's joystick widget uses.
    ///
    /// **2. Steering lives on `y` (roll) for Ackermann, and on `r` (yaw) for
    /// Differential.** PX4 v1.14+ rover modules diverge on which manual stick they
    /// read for the steering actuator:
    ///
    ///   - `RoverAckermann.cpp` MANUAL handler: `_rover_steering_setpoint = manual.roll`
    ///     (i.e. MAVLink `y / 1000`). Yaw stick is ignored — Ackermann can't pivot.
    ///   - `RoverDifferential.cpp` MANUAL handler: uses `manual.yaw` (MAVLink `r / 1000`)
    ///     because skid-steer rovers can rotate in place.
    ///
    /// We're agnostic to which module is loaded (SIH ships Ackermann; real hardware
    /// could be either), so we send the operator yaw-rate intent on **both** `y` and
    /// `r`. The active rover module reads its preferred field; the other is harmlessly
    /// ignored.
    ///
    /// The 30 Hz tick is critical: PX4's commander expects a continuous
    /// `manual_control_setpoint` stream and falls back to HOLD if the topic stops
    /// updating for ~0.5 s (RC-loss style failsafe).
    private func pushPX4GroundManualSetpoint(for intent: OperatorIntent) {
        let throttle01 = 0.5 + 0.5 * clamp(intent.forward)
        let steering = clamp(intent.yawRate)
        drone.manualControl.setManualControlInput(
            x: 0,
            y: Float(steering),
            z: Float(throttle01),
            r: Float(steering)
        )
        .subscribe(onCompleted: {}, onError: { _ in })
        .disposed(by: bag)
    }

    private func pushManualControlSetpoint(for intent: OperatorIntent) {
        // ManualControl axis convention (per MAVSDK, multicopter-flavoured):
        //   x = pitch (forward/back), y = roll (strafe),
        //   z = throttle (0…1, 0.5 = neutral hover), r = yaw.
        // For non-multicopter vehicles the autopilot maps these differently (e.g. ArduPilot
        // Rover MANUAL applies `z` to throttle and `r` to steering). Class-aware mapping
        // can land here when controller-input integration arrives.
        let throttle = clamp(0.5 + clamp(intent.up) * 0.5, lo: 0, hi: 1)
        drone.manualControl.setManualControlInput(
            x: Float(clamp(intent.forward)),
            y: Float(clamp(intent.right)),
            z: Float(throttle),
            r: Float(clamp(intent.yawRate))
        )
        .subscribe(onCompleted: {}, onError: { _ in })
        .disposed(by: bag)
    }

    private func clamp(_ v: Double, lo: Double = -1, hi: Double = 1) -> Double {
        max(lo, min(hi, v))
    }

    /// Bridge a single-shot RxSwift `Completable` to async/await. The Rx pipeline keeps
    /// itself alive until the terminal event fires, so dropping the returned `Disposable`
    /// is intentional and correct here.
    private func awaitCompletable(_ completable: Completable) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            _ = completable.subscribe(
                onCompleted: { cont.resume() },
                onError: { error in cont.resume(throwing: error) }
            )
        }
    }
}
