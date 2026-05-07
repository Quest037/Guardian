import Combine
import Foundation
import OSLog
import UserNotifications

/// Stable category identifiers for Paladin notifications (actions / grouping can attach here later).
enum PaladinNotificationCategory: String {
    case general = "com.calwest.guardianhq.paladin.general"
}

/// Payload discriminator in `userInfo["kind"]` — extend as you add notification shapes.
enum PaladinUserNotificationKind: String, Sendable {
    case planCompiled = "paladin.plan_compiled"
    case executionStarted = "paladin.execution_started"
    case runCompleted = "paladin.run_completed"
}

/// Local User Notifications for Paladin lifecycle and (later) high-signal events.
@MainActor
final class PaladinUserNotificationService: NSObject, ObservableObject {
    static let shared = PaladinUserNotificationService()

    private static let log = Logger(subsystem: "com.calwest.guardianhq", category: "PaladinNotifications")

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Ensures we only drive the permission dialog once per process; `configure()` may be called again after splash.
    private var didRequestAuthorizationThisSession = false

    private override init() {
        super.init()
    }

    /// Lines here go to **Xcode’s debug console** (⌘⇧Y → bottom pane → “All Output”) even when `Logger` / Console.app filters hide them.
    private static func trace(_ message: String) {
        print("[GuardianHQ][UserNotifications] \(message)")
        fflush(stdout)
    }

    /// `UNUserNotificationCenter.requestAuthorization` returns **UNError 1 (notificationsNotAllowed)** when the process is not running inside a real **`.app`** bundle (e.g. Xcode “Play” for a flat `Build/Products/Debug` product).
    private static var runsInsideApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    /// Idempotent: (re)install delegate + categories, then async bootstrap so `authorizationStatus` matches the system.
    func configure() {
        Self.trace("configure() on MainActor=\(Thread.isMainThread)")
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(with: center)
        let bid = Bundle.main.bundleIdentifier ?? "(nil)"
        let bundlePath = Bundle.main.bundlePath
        Self.trace("Bundle.main.bundleIdentifier=\(bid) bundlePath=\(bundlePath) runsInsideApplicationBundle=\(Self.runsInsideApplicationBundle)")
        if Bundle.main.bundleIdentifier == nil {
            Self.log.warning("Bundle.main.bundleIdentifier is nil — User Notifications may not register until the built product has a proper bundle id (e.g. full .app from Xcode archive).")
        }
        if !Self.runsInsideApplicationBundle {
            Self.trace(
                "User Notifications are disabled in this launch configuration: macOS only allows UNUserNotificationCenter for processes inside a .app bundle. Xcode is running a flat binary under Build/Products/…/Debug. Build “Guardian HQ.app” (macOS App target that depends on this package) or run: scripts/package-macos-app.sh && open \"build/Guardian HQ.app\""
            )
        }
        Task { @MainActor in
            await bootstrapAuthorizationIfNeeded()
        }
    }

    private func registerCategories(with center: UNUserNotificationCenter) {
        let general = UNNotificationCategory(
            identifier: PaladinNotificationCategory.general.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([general])
    }

    /// Reads current settings (async, no stale callback race), then requests authorization once while `.notDetermined`.
    private func bootstrapAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        Self.trace("notificationSettings authorizationStatus rawValue=\(settings.authorizationStatus.rawValue)")

        if settings.authorizationStatus == .notDetermined, !didRequestAuthorizationThisSession {
            if !Self.runsInsideApplicationBundle {
                Self.trace("Skipping requestAuthorization (not inside .app) — avoids UNErrorDomain error 1.")
            } else {
                didRequestAuthorizationThisSession = true
                // Brief delay: early launch + Xcode “Play” sometimes races TCC before a key window exists; permission UI is less likely to appear.
                try? await Task.sleep(nanoseconds: 400_000_000)
                Self.trace("calling requestAuthorization(options: alert,sound,badge)…")
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    Self.trace("requestAuthorization returned granted=\(granted)")
                    Self.log.info("User notification authorization request finished (granted=\(granted))")
                } catch {
                    Self.trace("requestAuthorization threw: \(error.localizedDescription)")
                    Self.log.error("User notification authorization request failed: \(error.localizedDescription)")
                }
            }
        }
        settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        Self.trace("bootstrap done final authorizationStatus rawValue=\(settings.authorizationStatus.rawValue)")
    }

    func refreshAuthorizationStatus() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    /// Posts immediately (no fire date). Uses `threadIdentifier` = `runID` so Notification Center groups by run.
    /// Always re-reads authorization asynchronously so delivery is not dropped while `authorizationStatus` is still catching up.
    func deliver(
        kind: PaladinUserNotificationKind,
        title: String,
        subtitle: String?,
        body: String,
        runID: UUID?
    ) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional: allowed = true
            case .notDetermined, .denied, .ephemeral: allowed = false
            @unknown default: allowed = false
            }
            guard allowed else {
                Self.trace("deliver skipped (authorizationStatus rawValue=\(settings.authorizationStatus.rawValue))")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            if let subtitle, !subtitle.isEmpty {
                content.subtitle = subtitle
            }
            content.body = body
            content.categoryIdentifier = PaladinNotificationCategory.general.rawValue
            content.sound = .default
            if let runID {
                content.threadIdentifier = runID.uuidString
            }
            var info: [String: Any] = [Self.userInfoKindKey: kind.rawValue]
            if let runID {
                info[Self.userInfoRunIDKey] = runID.uuidString
            }
            content.userInfo = info

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
                Self.trace("deliver posted kind=\(kind.rawValue)")
            } catch {
                Self.trace("deliver add failed: \(error.localizedDescription)")
                Self.log.error("Failed to add notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Typed helpers (add more as you experiment)

    func notifyPlanCompiled(runID: UUID, missionName: String) {
        deliver(
            kind: .planCompiled,
            title: "Paladin",
            subtitle: missionName,
            body: "Mission plan compiled and ready.",
            runID: runID
        )
    }

    func notifyExecutionStarted(runID: UUID, missionName: String) {
        deliver(
            kind: .executionStarted,
            title: "Paladin",
            subtitle: missionName,
            body: "Execution started.",
            runID: runID
        )
    }

    func notifyRunCompleted(runID: UUID, missionName: String, summary: String) {
        let maxLen = 320
        let trimmed = summary.count > maxLen ? String(summary.prefix(maxLen)) + "…" : summary
        deliver(
            kind: .runCompleted,
            title: "Paladin",
            subtitle: missionName,
            body: trimmed,
            runID: runID
        )
    }

    private static let userInfoKindKey = "paladin.kind"
    private static let userInfoRunIDKey = "paladin.runID"
}

// MARK: - UNUserNotificationCenterDelegate

extension PaladinUserNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
