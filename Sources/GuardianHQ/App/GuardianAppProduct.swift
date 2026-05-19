import Foundation

/// Which macOS app executable is running (Mission ops, Training lab, or full monolith during cutover).
public enum GuardianAppProduct: String, Sendable, CaseIterable {
    case fullHQ
    case mission
    case training

    public var displayName: String {
        switch self {
        case .fullHQ:
            return "Guardian HQ"
        case .mission:
            return "Guardian Mission"
        case .training:
            return "Guardian Training"
        }
    }

    /// Splash headline (uppercase styling applied in ``TacticalSplashView``).
    public var splashHeadline: String {
        switch self {
        case .fullHQ:
            return "GUARDIAN HQ"
        case .mission:
            return "GUARDIAN MISSION"
        case .training:
            return "GUARDIAN TRAINING"
        }
    }

    public var splashTagline: String {
        switch self {
        case .fullHQ:
            return "SECURE MISSION OPERATIONS"
        case .mission:
            return "FIELD MISSION OPERATIONS"
        case .training:
            return "AUTONOMY TRAINING LAB"
        }
    }

    /// Bundled PNG in the SwiftPM resource bundle (filename only).
    public var sidebarLogoResourceName: String {
        switch self {
        case .fullHQ, .mission:
            return "sidebar_logo"
        case .training:
            return "sidebar_logo_training"
        }
    }

    /// Tactical splash centre mark (`splash_logo_mission` / `splash_logo_training`).
    public var splashLogoResourceName: String {
        switch self {
        case .fullHQ, .mission:
            return "splash_logo_mission"
        case .training:
            return "splash_logo_training"
        }
    }

    /// Dock, Finder, and `.app` bundle icon source PNG (`dock_logo_mission` / `dock_logo_training`).
    public var dockLogoResourceName: String {
        switch self {
        case .fullHQ, .mission:
            return "dock_logo_mission"
        case .training:
            return "dock_logo_training"
        }
    }

    var defaultAppSection: AppSection {
        .dashboard
    }

    /// Whether an ``AppSection`` appears in the primary or secondary sidebar for this product.
    func includesSidebarSection(_ section: AppSection) -> Bool {
        switch self {
        case .fullHQ:
            return true
        case .mission:
            switch section {
            case .training, .worlds:
                return false
            default:
                return true
            }
        case .training:
            switch section {
            case .missions, .missionControl, .liveDrive, .brains:
                return false
            default:
                return true
            }
        }
    }

    /// Primary rail after simulate gating (Training tab only when simulate is on, except in the Training app).
    func primarySidebarRail(simulateEnabled: Bool) -> [AppSection] {
        let railSimulateEnabled = (self == .training) ? true : simulateEnabled
        var rail = AppSection.primarySidebarRail(simulateEnabled: railSimulateEnabled)
            .filter { includesSidebarSection($0) }
        if includesGazeboSimulation {
            if let trainingIndex = rail.firstIndex(of: .training) {
                rail.insert(.worlds, at: trainingIndex)
            } else if self == .training {
                rail.append(.worlds)
                if railSimulateEnabled, !rail.contains(.training) {
                    rail.append(.training)
                }
            }
        }
        return rail
    }

    func secondarySidebarSections() -> [AppSection] {
        AppSection.secondarySidebarSections.filter { includesSidebarSection($0) }
    }

    /// Gazebo 3D training worlds (Training lab + full monolith during cutover).
    var includesGazeboSimulation: Bool {
        switch self {
        case .training, .fullHQ:
            return true
        case .mission:
            return false
        }
    }
}
