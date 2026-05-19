import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Garage"
    case liveDrive = "Live Drive"
    case logs = "Logs"
    case missions = "Missions"
    case missionControl = "Mission Control"
    case theme = "Theme"
    case settings = "Settings"
    case plugins = "Plugins"
    case training = "Training"
    case worlds = "Worlds"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .devices:
            return "car.side"
        case .liveDrive:
            return "steeringwheel"
        case .missions:
            return "map"
        case .logs:
            return "list.bullet.rectangle.portrait"
        case .missionControl:
            return "slider.horizontal.3"
        case .training:
            return "graduationcap"
        case .worlds:
            return "globe.americas.fill"
        case .theme:
            return "paintpalette.fill"
        case .settings:
            return "gearshape.fill"
        case .plugins:
            return "puzzlepiece.extension.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "HQ mission and fleet overview."
        case .devices:
            return "Live and simulated vehicles on the link."
        case .liveDrive:
            return "Direct vehicle control and manual driving."
        case .missions:
            return "Create and manage mission plans."
        case .logs:
            return "Server and vehicle log streams."
        case .missionControl:
            return "Operate active missions in real time."
        case .training:
            return "Train movement skills and preview formation spacing on simulators."
        case .worlds:
            return "Author Gazebo training worlds, start and goal poses, and obstacles."
        case .theme:
            return "UI chrome catalog and layout defaults."
        case .settings:
            return "MAVSDK, link, and app preferences."
        case .plugins:
            return "Built-in integrations and assistants."
        }
    }
}

extension AppSection {
    /// Upper sidebar scroll area (core destinations + ``GuardianPluginSidebarPlacement/primary`` contributions).
    static var primarySidebarRail: [AppSection] {
        [.dashboard, .missions, .missionControl, .devices, .liveDrive, .logs]
    }

    /// Primary rail entries visible for the current session (simulate-only surfaces appended when enabled).
    static func primarySidebarRail(simulateEnabled: Bool) -> [AppSection] {
        var rail = primarySidebarRail
        if simulateEnabled {
            rail.append(.training)
        }
        return rail
    }

    /// Built-in entries for the lower ``GuardianPluginSidebarPlacement/secondary`` rail (Settings, Plugins), above version.
    /// Plugin rows using ``GuardianPluginSidebarPlacement/secondary`` render before these.
    static var secondarySidebarSections: [AppSection] {
        [.settings, .plugins]
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        if let logo = GuardianDockLogoAsset.nsImage(for: GuardianAppSessionBootstrap.activeProduct) {
            NSApp.applicationIconImage = logo
        }
        NSApp.activate(ignoringOtherApps: true)
        /// Defer one turn so SwiftUI has installed the ``WindowGroup`` window before we resize (not Full Screen — fills ``NSScreen/visibleFrame``).
        DispatchQueue.main.async { @MainActor in
            Self.resizePrimaryWindowToFillVisibleScreen()
        }
        Task { @MainActor in
            UserNotificationService.shared.configure()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                GuardianApplicationLifecycle.shared.applicationDidBecomeActive()
                UserNotificationService.shared.refreshAuthorizationStatus()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                GuardianApplicationLifecycle.shared.applicationWillResignActive()
            }
        }
    }

    /// Expands the main titled window to the largest usable rect (menu bar + Dock safe), without entering macOS Full Screen.
    private static func resizePrimaryWindowToFillVisibleScreen() {
        let window = NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.styleMask.contains(.titled) })
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        GuardianAppQuitCoordinator.shared.teardownForApplicationQuit()
    }
}

