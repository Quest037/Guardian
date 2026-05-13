import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Vehicles"
    case liveDrive = "Live Drive"
    case logs = "Logs"
    case missions = "Missions"
    case missionControl = "Mission Control"
    case theme = "Theme"
    case settings = "Settings"
    case plugins = "Plugins"

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

    /// Built-in entries for the lower ``GuardianPluginSidebarPlacement/secondary`` rail (Settings, Plugins), above version.
    /// Plugin rows using ``GuardianPluginSidebarPlacement/secondary`` render before these.
    static var secondarySidebarSections: [AppSection] {
        [.settings, .plugins]
    }
}

@main
struct GuardianHQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var selection: AppSection = .dashboard
    @State private var showingSplash = true
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var guardianConfirmOverlayHost = GuardianConfirmOverlayHost()
    @StateObject private var appDrawer = AppDrawer()
    @StateObject private var fleetLinkService = FleetLinkService()
    @StateObject private var sitlService = SitlService()
    @StateObject private var generalSettingsStore = GeneralSettingsStore()
    @StateObject private var osmRoutingService = OSMRoutingService()
    @StateObject private var pluginPreferences = PluginPreferencesStore()
    @StateObject private var operatorPromptReviewFocusController = OperatorPromptReviewFocusController()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Force-quit leaves PX4 / ArduPilot children; clear before any new SITL or MAVSDK work this session.
        GuardianSitlOrphanBlitz.kickoffFromColdLaunch()
    }

    var body: some Scene {
        WindowGroup("Guardian HQ") {
            Group {
                if showingSplash {
                    TacticalSplashView()
                } else {
                    // Theme 12.1 — window stack: RootView → AppDrawer → blocking confirm host → persistent operator toasts → ephemeral toasts (see `GuardianLayoutPatterns`).
                    RootView(
                        selection: $selection,
                        fleetLinkService: fleetLinkService,
                        sitlService: sitlService,
                        generalSettingsStore: generalSettingsStore
                    )
                        .withAppDrawer()
                        .withGuardianConfirmOverlayHost()
                        .withOperatorPromptPersistentToasts()
                        .withToasts()
                        .environmentObject(appDrawer)
                        .environmentObject(OperatorPromptCenter.shared)
                        .environmentObject(operatorPromptReviewFocusController)
                        .environmentObject(osmRoutingService)
                        .onAppear {
                            // SwiftPM / early launch: re-run after splash so permission + System Settings registration line up with a real NSApplication + window session.
                            UserNotificationService.shared.configure()
                        }
                }
            }
            // Single injection point for the window scene: ``ToastHost`` (``View/withToasts()``) and every
            // descendant must resolve the same ``ToastCenter`` instance — do not attach only inside the
            // post-splash branch or modifier-order bugs can strand auto-dismiss behind a stale host binding.
            .environmentObject(toastCenter)
            .onReceive(NotificationCenter.default.publisher(for: GuardianReserveSwapPostCommitOperatorToastNotification.name)) { note in
                guard let message = note.userInfo?[GuardianReserveSwapPostCommitOperatorToastNotification.messageKey] as? String else { return }
                let raw = note.userInfo?[GuardianReserveSwapPostCommitOperatorToastNotification.severityRawKey] as? String
                let style = GuardianFeedbackSeverity(rawValue: raw ?? "") ?? .error
                toastCenter.show(message, style: style, duration: 4.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: GuardianMissionRunSimCleanupOperatorToastNotification.name)) { note in
                guard let message = note.userInfo?[GuardianMissionRunSimCleanupOperatorToastNotification.messageKey] as? String else { return }
                let raw = note.userInfo?[GuardianMissionRunSimCleanupOperatorToastNotification.severityRawKey] as? String
                let style = GuardianFeedbackSeverity(rawValue: raw ?? "") ?? .warning
                toastCenter.show(message, style: style, duration: 4.5)
            }
            // Must be an ancestor of ``View/withGuardianConfirmOverlayHost()`` so ``GuardianConfirmOverlayRootModifier`` can resolve ``@EnvironmentObject`` (it wraps the drawer, not the other way around).
            .environmentObject(guardianConfirmOverlayHost)
            .onChange(of: showingSplash) { stillShowingSplash in
                guard !stillShowingSplash else { return }
                Task { @MainActor in
                    UserNotificationService.shared.configure()
                }
            }
            .environmentObject(pluginPreferences)
            .environmentObject(GuardianPluginRegistry.shared)
            .onAppear {
                sitlService.attachFleetLink(fleetLinkService)
                GuardianPluginRegistry.shared.bindPreferences(pluginPreferences)
                GuardianPluginBootstrap.ensureRegistered()
                FleetCommandsCatalogueBootstrap.ensureRegistered()
                FleetRecipesCatalogueBootstrap.ensureRegistered()
            }
            .task {
                guard showingSplash else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(GuardianMotion.shellCrossfade) {
                    showingSplash = false
                }
            }
            .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1320, height: 860)
    }

    private var preferredColorScheme: ColorScheme? {
        switch generalSettingsStore.appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let logo = AppIconLoader.loadLogoIcon() {
            NSApp.applicationIconImage = logo
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            UserNotificationService.shared.configure()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                UserNotificationService.shared.refreshAuthorizationStatus()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // AppKit invokes this on the main thread; run inline so MainActor work does not deadlock.
        MainActor.assumeIsolated {
            GuardianAppQuitCoordinator.shared.teardownForApplicationQuit()
        }
    }
}

private enum AppIconLoader {
    static func loadLogoIcon() -> NSImage? {
        guard let bundledURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: bundledURL)
    }
}
