import SwiftUI

/// Central **durations** and **preset animations** for GuardianHQ chrome (Theme §5).
///
/// ### Ease vs spring (operator UI)
/// - Use **ease** presets here for **window-level** and **persistent chrome**: confirms, drawers, sidebar width, toasts, bottom prompts — predictable timing in dense HUDs.
/// - Reserve **springs** for bounded **in-screen** mechanics (e.g. a view-owned sidebar inside Mission workspace). Do not default window overlays to springs unless product explicitly wants overshoot.
///
/// ### Surfaces without built-in motion
/// - ``GuardianInlineNotice`` is a **static** surface; it does not apply enter/exit animation itself. Animate the **container** (e.g. `List` row insertion) if motion is required.
enum GuardianMotion {

    // MARK: - Durations (seconds)

    /// Confirm overlay panel + scrim (``GuardianConfirmOverlayHost``).
    static let confirmPulseSeconds: Double = 0.16

    /// Toasts and bottom prompt banner show/hide.
    static let feedbackMicroInteractionSeconds: Double = 0.18

    /// App drawer slide, main sidebar expand/collapse, Live Drive / MC sidebars.
    static let chromeDrawerSeconds: Double = 0.2

    /// Splash → main shell cross-fade.
    static let shellTransitionSeconds: Double = 0.25

    // MARK: - Presets (`withAnimation` / `.animation(_:value:)`)

    static var confirmPresent: Animation { .easeOut(duration: confirmPulseSeconds) }

    static var feedbackCrossfade: Animation { .easeInOut(duration: feedbackMicroInteractionSeconds) }

    static var drawerSlide: Animation { .easeInOut(duration: chromeDrawerSeconds) }

    static var shellCrossfade: Animation { .easeInOut(duration: shellTransitionSeconds) }
}
