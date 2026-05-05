import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Devices"
    case missions = "Missions"
    case missionControl = "Mission Control"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "HQ mission and fleet overview."
        case .devices:
            return "Manage connected devices."
        case .missions:
            return "Create and manage mission plans."
        case .missionControl:
            return "Operate active missions in real time."
        }
    }
}

@main
struct GuardianHQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var selection: AppSection = .dashboard
    @State private var showingSplash = true
    @StateObject private var toastCenter = ToastCenter()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Guardian HQ") {
            Group {
                if showingSplash {
                    TacticalSplashView()
                } else {
                    RootView(selection: $selection)
                        .withToasts()
                        .environmentObject(toastCenter)
                }
            }
            .preferredColorScheme(.dark)
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
