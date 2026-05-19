import Foundation

extension Notification.Name {
    /// Posted on the main queue when the app becomes active again (after `willResignActive`).
    static let guardianApplicationDidBecomeActive = Notification.Name("guardian.application.didBecomeActive")
}

/// macOS app active / background policy for lab runs (Training teaching + fleet ROS).
@MainActor
final class GuardianApplicationLifecycle: ObservableObject {
    static let shared = GuardianApplicationLifecycle()

    @Published private(set) var isApplicationActive = true

    private weak var fleetLink: FleetLinkService?
    private var backgroundLabRunCount = 0
    private var appNapPreventionToken: NSObjectProtocol?

    private init() {}

    func noteFleetLinkService(_ service: FleetLinkService) {
        fleetLink = service
    }

    /// Call from `NSApplicationDelegate` / app shell when the app resigns active.
    func applicationWillResignActive() {
        setApplicationActive(false)
    }

    /// Call when the app becomes active again.
    func applicationDidBecomeActive() {
        setApplicationActive(true)
    }

    /// Autonomous teaching (or other unattended lab work): keep subprocesses warm and reduce App Nap.
    func beginBackgroundLabRun() {
        backgroundLabRunCount += 1
        if backgroundLabRunCount == 1 {
            appNapPreventionToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Guardian Training lab run"
            )
        }
        if !isApplicationActive {
            fleetLink?.resumeFleetNav2AfterApplicationBackground()
        }
    }

    func endBackgroundLabRun() {
        guard backgroundLabRunCount > 0 else { return }
        backgroundLabRunCount -= 1
        if backgroundLabRunCount == 0 {
            if let token = appNapPreventionToken {
                ProcessInfo.processInfo.endActivity(token)
                appNapPreventionToken = nil
            }
            if !isApplicationActive {
                applyBackgroundFleetPolicy()
            }
        }
    }

    var isBackgroundLabRunActive: Bool { backgroundLabRunCount > 0 }

    /// When false, ROS bridge stdout is not scheduled on the main actor (map UI is paused).
    var shouldDeliverRosBridgeStdoutToMainActor: Bool {
        isApplicationActive
    }

    private func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
        if active {
            fleetLink?.resumeFleetNav2AfterApplicationBackground()
            fleetLink?.flushDeferredHubTelemetryTickIfNeeded()
            NotificationCenter.default.post(name: .guardianApplicationDidBecomeActive, object: nil)
        } else {
            applyBackgroundFleetPolicy()
        }
    }

    private func applyBackgroundFleetPolicy() {
        if backgroundLabRunCount > 0 {
            return
        }
        fleetLink?.pauseFleetNav2ForApplicationBackground()
    }
}
