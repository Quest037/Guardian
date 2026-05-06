import Foundation

/// Inner navigation for the Settings sidebar section (segmented control).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"

    var id: String { rawValue }
}
