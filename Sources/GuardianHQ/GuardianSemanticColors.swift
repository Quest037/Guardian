import SwiftUI

/// App-wide semantic colors (aligned with toast / status meaning).
enum GuardianSemanticColors {
    /// Success — same family as `ToastStyle.success` background tint.
    static let successBackground = Color.green.opacity(0.22)
    static let successForeground = Color.green

    /// Warning — same translucency pattern as success; use for setup / caution badges.
    static let warningBackground = Color.yellow.opacity(0.22)
    static let warningForeground = Color.yellow.opacity(0.92)

    static let neutralBadgeBackground = Color.white.opacity(0.1)
    static let neutralBadgeForeground = Color.gray.opacity(0.95)
}
