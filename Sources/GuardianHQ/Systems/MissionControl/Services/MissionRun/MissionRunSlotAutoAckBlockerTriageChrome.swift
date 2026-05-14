import SwiftUI

/// MC-R task triage **slot blocker** row chrome (§3 auto mission-end ack wait list): severity rail + row wash + label tint from ``GuardianSemanticColors`` / ``GuardianThemePalette`` (``TaskRosterAssignmentStatesToDo.md`` §6 theme).
enum MissionRunSlotAutoAckBlockerTriageChrome {
    /// Stable token for tests (maps 1:1 with roster chip severity when present).
    enum RailToken: String, Equatable {
        case danger
        case warning
        case info
        case success
        case neutral
    }

    static func railToken(for merged: MissionRunAssignmentSlotState) -> RailToken {
        guard let sev = merged.missionControlRosterBadgeSeverity else { return .neutral }
        switch sev {
        case .error:
            return .danger
        case .warning:
            return .warning
        case .info:
            return .info
        case .success:
            return .success
        }
    }

    static func railColor(for merged: MissionRunAssignmentSlotState, neutralRail: Color) -> Color {
        switch railToken(for: merged) {
        case .danger:
            return GuardianSemanticColors.dangerStroke
        case .warning:
            return GuardianSemanticColors.warningStroke
        case .info:
            return GuardianSemanticColors.infoForeground
        case .success:
            return GuardianSemanticColors.successStroke
        case .neutral:
            return neutralRail
        }
    }

    static func labelForeground(for merged: MissionRunAssignmentSlotState, neutralText: Color) -> Color {
        guard let sev = merged.missionControlRosterBadgeSeverity else { return neutralText }
        switch sev {
        case .error:
            return GuardianSemanticColors.dangerForeground
        case .warning:
            return GuardianSemanticColors.warningForeground
        case .info:
            return GuardianSemanticColors.infoForeground
        case .success:
            return GuardianSemanticColors.successForeground
        }
    }

    /// Subtle per-row wash behind slot name + merged state (``Color.clear`` when severity is absent).
    static func rowHighlightFill(for merged: MissionRunAssignmentSlotState) -> Color {
        guard let sev = merged.missionControlRosterBadgeSeverity else { return Color.clear }
        switch sev {
        case .error:
            return GuardianSemanticColors.dangerBackground.opacity(0.42)
        case .warning:
            return GuardianSemanticColors.warningBackground.opacity(0.5)
        case .info:
            return GuardianSemanticColors.infoBackground.opacity(0.42)
        case .success:
            return GuardianSemanticColors.successBackground.opacity(0.48)
        }
    }
}