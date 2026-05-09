import SwiftUI

/// App-wide semantic colors (aligned with toast / status meaning).
enum GuardianSemanticColors {
    /// Success — same family as `ToastStyle.success` background tint.
    static let successBackground = Color.green.opacity(0.22)
    static let successForeground = Color.green

    /// Warning — amber-tinted surface; foreground stays **dark** so text stays legible on the yellow/amber fill in every appearance (badges, pills, banners).
    static let warningBackground = Color(red: 0.98, green: 0.86, blue: 0.42).opacity(0.36)
    static let warningForeground = Color.black.opacity(0.88)

    /// Info (e.g. completed / neutral-positive emphasis).
    static let infoBackground = Color.blue.opacity(0.22)
    static let infoForeground = Color.blue.opacity(0.92)

    /// Danger / error emphasis.
    static let dangerBackground = Color.red.opacity(0.24)
    static let dangerForeground = Color.red.opacity(0.92)

    static let neutralBadgeBackground = Color.white.opacity(0.1)
    static let neutralBadgeForeground = Color.gray.opacity(0.95)

    /// Paladin session phase badge: pre-execution states use warning; live execution success; completed info; failed danger.
    static func paladinPhaseBadgeStyle(for phase: MissionRunSessionPhase) -> (background: Color, foreground: Color) {
        switch phase {
        case .draft, .compiled, .staging:
            return (warningBackground, warningForeground)
        case .executing:
            return (successBackground, successForeground)
        case .completed:
            return (infoBackground, infoForeground)
        case .failed:
            return (dangerBackground, dangerForeground)
        }
    }
}
