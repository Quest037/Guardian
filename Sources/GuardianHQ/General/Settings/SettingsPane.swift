import Foundation

/// Inner navigation for the Settings sidebar section (segmented control).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case missions = "Missions"
    case sims = "SIMs"
    case liveDrive = "Live Drive"
    case controls = "Controls"

    var id: String { rawValue }
}
