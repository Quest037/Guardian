import SwiftUI

/// App-wide semantic colors (aligned with toast / status meaning).
enum GuardianSemanticColors {
    /// Success — same family as ``GuardianFeedbackSeverity/success`` / legacy toast chip tint.
    static let successBackground = Color.green.opacity(0.22)
    static let successForeground = Color.green
    /// Vivid success accent for strokes / icons / dots / emphasis text on neutral surfaces.
    static let successStroke = Color.green.opacity(0.92)

    /// Warning — amber-tinted surface; foreground stays **dark** so text stays legible on the yellow/amber fill in every appearance (badges, pills, banners).
    static let warningBackground = Color(red: 0.98, green: 0.86, blue: 0.42).opacity(0.36)
    static let warningForeground = Color.black.opacity(0.88)
    /// Vivid warning accent for strokes / icons / dots / emphasis text on neutral surfaces — uses orange instead of plain yellow for legibility on light-gray panels.
    static let warningStroke = Color.orange.opacity(0.95)

    /// Info (e.g. completed / neutral-positive emphasis).
    static let infoBackground = Color.blue.opacity(0.22)
    static let infoForeground = Color.blue.opacity(0.92)

    /// Danger / error emphasis.
    static let dangerBackground = Color.red.opacity(0.24)
    static let dangerForeground = Color.red.opacity(0.92)
    /// Vivid danger accent for strokes / icons / dots / emphasis text (mirrors ``dangerForeground``).
    static let dangerStroke = Color.red.opacity(0.92)

    static let neutralBadgeBackground = Color.white.opacity(0.1)
    static let neutralBadgeForeground = Color.gray.opacity(0.95)

    // MARK: - Bottom prompt banners (opaque; Theme §10.3)

    /// Solid fills for ``GuardianBottomPromptBanner`` (white text). Tuned from ``successStroke`` / ``infoForeground`` / ``warningStroke`` / ``dangerStroke`` families for contrast on sheet backgrounds — adjust here + Theme plugin together.
    static let bottomPromptBannerSuccess = Color(red: 0.09, green: 0.46, blue: 0.24)
    static let bottomPromptBannerInfo = Color(red: 0.12, green: 0.35, blue: 0.68)
    static let bottomPromptBannerWarning = Color(red: 0.52, green: 0.38, blue: 0.08)
    static let bottomPromptBannerError = Color(red: 0.58, green: 0.14, blue: 0.17)

    /// Paladin session phase badge: pre-execution states use warning; live execution success; completed info; failed danger.
    static func paladinPhaseBadgeStyle(for phase: MissionRunSessionPhase) -> (background: Color, foreground: Color) {
        switch phase {
        case .draft, .compiled, .staging:
            return (warningBackground, warningForeground)
        case .executing:
            return (successBackground, successForeground)
        case .recovery:
            return (infoBackground, infoForeground)
        case .completed:
            return (infoBackground, infoForeground)
        case .aborting, .aborted:
            return (dangerBackground, dangerForeground)
        }
    }
}
