import SwiftUI

// MARK: - Canonical severity (Theme §4)

/// Shared **severity** for operator feedback across toasts, bottom prompts, inline notices, and related chrome.
///
/// ## Channel decision table
///
/// | Channel | Scope | Blocks interaction? | Typical persistence | Notes |
/// | --- | --- | --- | --- | --- |
/// | **Toast** (`ToastCenter` / `View/withToasts()`) | Window · **top-leading** over the main **content** column | No | Auto-dismiss (default ≈2.2s) | Single slot; does not cover the sidebar rail. |
/// | **Bottom prompt** (`GuardianBottomPromptCenter` / `GuardianBottomPromptBanner`) | **Screen-local** (host owns the center, e.g. Mission Control run, Live Drive) | Optional two-button flows gate the next step | Until dismissed or confirmed | Solid bottom banner; heavier than a toast. |
/// | **Inline notice** (`GuardianInlineNotice`) | **Screen-local** (embedded in a layout) | No | Until your state removes it | Raised surface + border; use for contextual callouts. |
/// | **Confirm** (`guardianConfirmOverlay` + `GuardianConfirmOverlayHost`) | **Whole window** | **Yes** (dimmed scrim) | Until action or Escape | Highest shell band in practice — see z-order below. |
///
/// ## Z-order and attention (shell)
///
/// **Back → front:** ``RootView`` (sidebar + `content`, with ``View/withToasts()`` on the content column only) →
/// ``View/withAppDrawer()`` (full-window scrim + trailing panel) → ``View/withGuardianConfirmOverlayHost()`` (global
/// blocking scrim + panel). An open drawer covers toasts; a presented confirm covers the drawer and all chrome. See
/// ``GuardianLayoutPatterns`` for the canonical stack and modifier order. Bottom prompts live inside feature stacks; if
/// a blocking confirm could appear, dismiss the prompt first so the two never compete for the same decision.
///
/// ## Naming bridge
///
/// ``GuardianInlineNoticeKind`` uses `.danger` for the same tone as **`.error`** here. Use ``GuardianInlineNoticeKind/feedbackSeverity`` when mapping.
enum GuardianFeedbackSeverity: String, CaseIterable, Equatable, Hashable, Sendable {
    case success
    case info
    case warning
    case error

    /// Primary SF Symbol for **toast** and **bottom prompt** chrome (shared recipe).
    var feedbackChromeSymbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    /// Back-compat alias for call sites that still say ``ToastStyle/icon``.
    var icon: String { feedbackChromeSymbol }

    /// Legacy translucent chip fill (prefer ``ToastHost`` solid fills for new UI).
    var legacyTranslucentChipBackground: Color {
        switch self {
        case .success: GuardianSemanticColors.successBackground
        case .info: GuardianSemanticColors.infoBackground
        case .warning: GuardianSemanticColors.warningBackground
        case .error: GuardianSemanticColors.dangerBackground
        }
    }
}

/// Back-compat: existing call sites use ``ToastStyle``.
typealias ToastStyle = GuardianFeedbackSeverity

/// Back-compat: bottom prompts use the same four cases as ``GuardianFeedbackSeverity``.
typealias GuardianBottomPromptStyle = GuardianFeedbackSeverity

extension GuardianFeedbackSeverity {
    /// Ephemeral **toast** chip fill (solid, high-contrast on ``ToastHost``).
    var toastEphemeralSolidBackground: Color {
        switch self {
        case .success:
            return Color(red: 0.11, green: 0.44, blue: 0.24).opacity(0.82)
        case .info:
            return Color(red: 0.14, green: 0.34, blue: 0.62).opacity(0.82)
        case .warning:
            return Color(red: 0.52, green: 0.38, blue: 0.08).opacity(0.82)
        case .error:
            return Color(red: 0.52, green: 0.14, blue: 0.18).opacity(0.82)
        }
    }

    /// Solid **bottom prompt** banner fill — uses ``GuardianSemanticColors`` opaque banner tokens (Theme §10.3).
    var bottomPromptBannerBackground: Color {
        switch self {
        case .success: GuardianSemanticColors.bottomPromptBannerSuccess
        case .info: GuardianSemanticColors.bottomPromptBannerInfo
        case .warning: GuardianSemanticColors.bottomPromptBannerWarning
        case .error: GuardianSemanticColors.bottomPromptBannerError
        }
    }
}
