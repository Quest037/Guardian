import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Vehicles"
    case liveDrive = "Live Drive"
    case logs = "Logs"
    case missions = "Missions"
    case missionControl = "Mission Control"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .devices:
            return "dot.radiowaves.left.and.right"
        case .liveDrive:
            return "steeringwheel"
        case .missions:
            return "map"
        case .logs:
            return "list.bullet.rectangle.portrait"
        case .missionControl:
            return "slider.horizontal.3"
        case .settings:
            return "gearshape.fill"
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
        case .settings:
            return "MAVSDK, link, and app preferences."
        }
    }
}

@main
struct GuardianHQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var selection: AppSection = .dashboard
    @State private var showingSplash = true
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var fleetLinkService = FleetLinkService()
    @StateObject private var sitlService = SitlService()

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
                    RootView(selection: $selection, fleetLinkService: fleetLinkService, sitlService: sitlService)
                        .withToasts()
                        .environmentObject(toastCenter)
                        .onAppear {
                            // SwiftPM / early launch: re-run after splash so permission + System Settings registration line up with a real NSApplication + window session.
                            PaladinUserNotificationService.shared.configure()
                        }
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: showingSplash) { stillShowingSplash in
                guard !stillShowingSplash else { return }
                Task { @MainActor in
                    PaladinUserNotificationService.shared.configure()
                }
            }
            .onAppear {
                sitlService.attachFleetLink(fleetLinkService)
            }
            .task {
                guard showingSplash else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingSplash = false
                }
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1320, height: 860)
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
            PaladinUserNotificationService.shared.configure()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PaladinUserNotificationService.shared.refreshAuthorizationStatus()
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
