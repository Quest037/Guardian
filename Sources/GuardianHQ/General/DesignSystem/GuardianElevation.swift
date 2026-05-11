import SwiftUI

// MARK: - Surface levels (Theme §3.1)

/// Conceptual **surface stack** for operator UI — maps to ``GuardianThemePalette`` fills.
///
/// Ordering: **base** (window) → **raised** (cards, inset panels) → **elevated** (metric tiles, nested strips) → **active** (selection / pressed).
/// Full-window **overlay scrim** lives on the palette as ``GuardianThemePalette/overlayScrim`` (modal hosts apply it separately from fills).
enum GuardianSurfaceLevel: CaseIterable, Hashable, Sendable {
    case base
    case raised
    case elevated
    case active

    /// Theme catalog / debug label matching ``GuardianThemePalette`` property names.
    var catalogLabel: String {
        switch self {
        case .base: "backgroundBase"
        case .raised: "backgroundRaised"
        case .elevated: "backgroundElevated"
        case .active: "backgroundActive"
        }
    }

    func fill(from palette: GuardianThemePalette) -> Color {
        switch self {
        case .base: palette.backgroundBase
        case .raised: palette.backgroundRaised
        case .elevated: palette.backgroundElevated
        case .active: palette.backgroundActive
        }
    }
}

// MARK: - Drop shadows (Theme §3.2)

/// Shared **drop shadow** recipes. Prefer these over ad-hoc ``View/shadow`` tuples so confirms, toasts, and notices stay aligned (Theme §3.3).
enum GuardianElevation {
    struct DropShadow: Sendable {
        let color: Color
        var radius: CGFloat
        var x: CGFloat = 0
        var y: CGFloat
    }

    /// Window-level **confirm** / modal panel (``GuardianConfirmOverlayHost``).
    static let overlayPanel = DropShadow(color: Color.black.opacity(0.22), radius: 28, y: 14)

    /// Heavy **inspector** / floating sheet shell (e.g. Vehicle Inspector).
    static let inspectorPanel = DropShadow(color: Color.black.opacity(0.22), radius: 18, y: 10)

    /// **Ephemeral feedback** — toast chip, bottom prompt banner, ``GuardianInlineNotice`` (identical treatment).
    static let feedbackChrome = DropShadow(color: Color.black.opacity(0.18), radius: 12, y: 6)

    /// **Map** toolbar / WebView bezel (Leaflet-adjacent tight lift).
    static let mapToolbarBezel = DropShadow(color: Color.black.opacity(0.22), radius: 1, y: 1)

    /// Optional **card** lift beyond hairline border — not applied by ``GuardianCard`` until product asks for depth.
    static let raisedCard = DropShadow(color: Color.black.opacity(0.12), radius: 8, y: 4)

    /// **Popover** / anchored panel (menus, compact inspectors).
    static let raisedPopover = DropShadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
}

extension View {
    /// Applies a ``GuardianElevation/DropShadow`` as SwiftUI ``View/shadow(color:radius:x:y:)``.
    func guardianDropShadow(_ spec: GuardianElevation.DropShadow) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}
