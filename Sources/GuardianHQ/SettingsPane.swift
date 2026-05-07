import Foundation

/// Inner navigation for the Settings sidebar section (segmented control).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case sims = "SIMs"
    case controls = "Controls"

    var id: String { rawValue }
}
