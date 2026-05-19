import Foundation
import SwiftUI

/// Side rail / drawer destinations for the unified Training lab (one view body each, two hosts).
enum TrainingLabPanelTab: String, CaseIterable, Identifiable, Sendable {
    case map = "Map"
    case vehicles = "Vehicles"
    case training = "Training"
    case logs = "Logs"

    var id: String { rawValue }

    var drawerTitle: String {
        switch self {
        case .map: return "Training map"
        case .vehicles: return "Vehicles"
        case .training: return "Training"
        case .logs: return "Logs"
        }
    }

    /// Sub-bar icon (SF Symbols).
    var systemImage: String {
        switch self {
        case .map: return "map"
        case .vehicles: return "car.side"
        case .training: return "gearshape"
        case .logs: return AppSection.logs.systemImage
        }
    }
}

enum TrainingLabLayout {
    /// Idle layout: main viewport fraction (map / Gazebo).
    static let viewportWidthFraction: CGFloat = 0.7
    /// Running-session drawer width (matches ``TrainingLabPanelView``).
    static let runningDrawerWidth: CGFloat = 400
}

/// Keyboard policy for ``TrainingLabPanelView`` (Theme catalog documents these).
enum TrainingLabKeyboardShortcuts {
    /// Start teaching or formation follow when the roster is ready (idle only).
    static let run = KeyboardShortcut.defaultAction

    /// Open a rail tab (idle) or the matching drawer (while a session is running).
    static func panelTab(_ tab: TrainingLabPanelTab) -> KeyboardShortcut {
        switch tab {
        case .map: KeyboardShortcut("1", modifiers: .command)
        case .vehicles: KeyboardShortcut("2", modifiers: .command)
        case .training: KeyboardShortcut("3", modifiers: .command)
        case .logs: KeyboardShortcut("4", modifiers: .command)
        }
    }

    /// Operator-facing summary for Theme / help copy.
    static var catalogSummaryLines: [String] {
        [
            "Return — Run (idle, when roster is ready)",
            "Escape — Stop session (running, when no drawer is open)",
            "⌘1–⌘4 — Map / Vehicles / Training / Logs (rail or drawer)",
        ]
    }
}
