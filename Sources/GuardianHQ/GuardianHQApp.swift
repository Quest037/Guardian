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
    @StateObject private var toastCenter = ToastCenter()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Guardian HQ") {
            RootView(selection: $selection)
                .preferredColorScheme(.dark)
                .withToasts()
                .environmentObject(toastCenter)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1320, height: 860)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
