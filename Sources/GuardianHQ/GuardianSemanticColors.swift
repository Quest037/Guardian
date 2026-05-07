import SwiftUI

/// App-wide semantic colors (aligned with toast / status meaning).
enum GuardianSemanticColors {
    /// Success — same family as `ToastStyle.success` background tint.
    static let successBackground = Color.green.opacity(0.22)
    static let successForeground = Color.green

    /// Warning — same translucency pattern as success; use for setup / caution badges.
    static let warningBackground = Color.yellow.opacity(0.22)
    static let warningForeground = Color.yellow.opacity(0.92)

    /// Info (e.g. completed / neutral-positive emphasis).
    static let infoBackground = Color.blue.opacity(0.22)
    static let infoForeground = Color.blue.opacity(0.92)

    /// Danger / error emphasis.
    static let dangerBackground = Color.red.opacity(0.24)
    static let dangerForeground = Color.red.opacity(0.92)

    static let neutralBadgeBackground = Color.white.opacity(0.1)
    static let neutralBadgeForeground = Color.gray.opacity(0.95)

    /// Paladin session phase badge: pre-execution states use warning; live execution success; completed info; failed danger.
    static func paladinPhaseBadgeStyle(for phase: PaladinSessionPhase) -> (background: Color, foreground: Color) {
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
