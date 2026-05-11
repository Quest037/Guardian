import SwiftUI

// MARK: - Keyboard, focus & VoiceOver (Theme §9)

/// ## §9.1 — Default button, Escape, Return
///
/// - **Window confirms** (`GuardianConfirmOverlayHost`): **Escape** dismisses the overlay when the host is key (macOS 14+ `onKeyPress` on the overlay root). **Standard** confirms attach **Return** to the blue affirmative via ``KeyboardShortcut/defaultAction``; **danger** confirms intentionally omit **Return → proceed** so accidental keyboard commit is harder — operator must click the red button.
/// - **Trailing drawers** (`AppDrawer`): **Escape** via ``View/onExitCommand``; chrome close uses ``KeyboardShortcut/cancelAction`` in ``AppDrawerChrome``.
/// - **Sheets using ``Modal``**: place dismiss on the **leading** side with ``KeyboardShortcut/cancelAction``; map **Save / primary** with ``KeyboardShortcut/defaultAction`` when there is a single obvious default.
///
/// ## §9.2 — Focus ring token
///
/// Use ``GuardianFocusRing`` for custom **`.plain`** hit targets that participate in keyboard focus. Prefer system `Button` / `ControlGroup` focus when possible.
///
/// ## §9.3 — Icon-only chrome (checklist)
///
/// 1. **`accessibilityLabel`**: short role (“Close”, “Open Vehicle Inspector”).
/// 2. **`accessibilityHint`**: outcome when non-obvious (“Discards edits and closes the sheet”).
/// 3. **`help`**: pointer tooltip; keep in sync with hint when practical.
/// 4. If the same symbol repeats, **differentiate** labels/hints per context.
///
/// ## §9.4 — Color-only state
///
/// Critical success / failure / blocking states must ship **icon + text** (or text alone), not color swatches alone — see ``GuardianInlineNotice``, ``GuardianInlineError``, ``GuardianFeedbackSeverity`` toasts, ``GuardianConfirm`` headers.

// MARK: - Focus ring (§9.2)

/// Stroke used when drawing a **custom** keyboard focus ring for `.plain` controls.
enum GuardianFocusRing {
    static let lineWidth: CGFloat = 2

    static func strokeColor(for colorScheme: ColorScheme) -> Color {
        GuardianSemanticColors.infoForeground.opacity(colorScheme == .dark ? 0.95 : 0.88)
    }
}

private struct GuardianKeyboardFocusRingModifier: ViewModifier {
    let show: Bool
    var cornerRadius: CGFloat = 6

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(GuardianFocusRing.strokeColor(for: colorScheme), lineWidth: GuardianFocusRing.lineWidth)
                .opacity(show ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Custom **keyboard focus** outline for `.plain` buttons when `show` reflects `@FocusState` / `isFocused`.
    func guardianKeyboardFocusRing(show: Bool, cornerRadius: CGFloat = 6) -> some View {
        modifier(GuardianKeyboardFocusRingModifier(show: show, cornerRadius: cornerRadius))
    }
}
