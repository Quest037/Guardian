import Foundation

/// Inner navigation for the Settings sidebar section (segmented control).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case missions = "Missions"
    case brains = "Brains"
    case sims = "SIMs"
    case liveDrive = "Live Drive"
    case controls = "Controls"

    var id: String { rawValue }

    /// Mission / HQ apps import brain packs; Training exports only.
    static func visiblePanes(for product: GuardianAppProduct) -> [SettingsPane] {
        allCases.filter { pane in
            switch pane {
            case .brains:
                return product.includesSidebarSection(.missions)
            default:
                return true
            }
        }
    }
}
