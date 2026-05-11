import SwiftUI

/// Navigation shell, **window stacking**, and **split / inspector** conventions (Theme §12).
///
/// ## Window-level modifier order (`GuardianHQApp`)
///
/// Attach window-scoped hosts **outside** ``RootView`` in this order so hit-testing and scrims stay predictable:
///
/// 1. ``RootView`` — app navigation rail, top bar, and feature `content`.
/// 2. ``View/withAppDrawer()`` — app-wide **trailing drawer** (scrim + panel). Not the main nav rail.
/// 3. ``View/withGuardianConfirmOverlayHost()`` — **blocking** confirm scrim + panel over the whole stack.
///
/// ```swift
/// RootView(...)
///     .withAppDrawer()
///     .withGuardianConfirmOverlayHost()
/// ```
///
/// ``ToastCenter`` / ``View/withToasts()`` is applied **inside** ``RootView`` on the main **content** column only
/// (toasts stay off the nav rail).
///
/// ## Back-to-front visual stack (single main window)
///
/// 1. **Navigation chrome** — ``RootView`` sidebar + top bar + feature content (maps, tables, etc.).
/// 2. **Toasts** — ``ToastHost`` overlays only the **content** column (below the top bar, beside the rail).
/// 3. **App drawer** — ``AppDrawerHostModifier`` draws a full-window scrim and trailing panel **above** the entire
///    ``RootView``, so an open drawer covers toasts as well as the rail.
/// 4. **Blocking confirm** — ``GuardianConfirmOverlayRootModifier`` wraps the drawer stack; the live panel uses a
///    high ``zIndex`` so a presented confirm sits **above** an open drawer and dims everything under it.
///
/// Screen-local feedback (bottom prompts, inline notices) lives inside feature stacks — see
/// ``GuardianFeedbackSeverity``. If a blocking confirm can appear, dismiss or avoid overlapping prompts first.
///
/// ## Trailing slide-in panels
///
/// Prefer ``AppDrawer`` for app-wide trailing panels. Avoid ad-hoc root ``ZStack`` scrims + manual slide transitions
/// for the same pattern — keep one host so Z-order and dismissal stay consistent with this document.
///
/// ## Split views and inspectors (Theme §12.2)
///
/// The shell is a **two-pane** layout today: a fixed-width **navigation rail** plus a flexible **content** region
/// (see ``RootView``). Additional **list / detail / inspector** columns should usually live **inside** `content`
/// (e.g. ``NavigationSplitView`` or ``HSplitView``) rather than widening the app rail.
///
/// When adding columns:
/// - **Collapse priority:** collapse optional inspectors and secondary lists before shrinking the primary mission /
///   map surface; keep the nav rail width policy in ``RootView`` unless you intentionally redesign the shell.
/// - **Minimum widths:** keep a usable primary canvas — on tight windows, prefer hiding a secondary column over
///   compressing telemetry text below readable caps. Use ``InspectorRails`` as a starting band, then tune per screen.
/// - **Persistence:** if split fractions are user-adjustable, persist sensible defaults and respect accessibility
///   / Dynamic Type by allowing vertical scroll in inspector stacks rather than infinite horizontal shrink.
enum GuardianLayoutPatterns {

    /// Suggested width bands when introducing a trailing inspector or browser column **inside** `content` (not the
    /// app nav rail). Call sites may clamp further (e.g. ``AppDrawer`` clamps 260–560pt).
    enum InspectorRails {
        /// Soft minimum for the main working area (maps, timelines) before a secondary column should yield.
        static let recommendedMinimumPrimaryCanvasWidth: CGFloat = 480
        /// Typical comfortable range for a single inspector / browser strip.
        static let recommendedInspectorPreferredWidthRange: ClosedRange<CGFloat> = 260...400
    }
}
