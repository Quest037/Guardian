import SwiftUI

/// Guardian iconography: **SF Symbol sizing** aligned to chrome rows and typography roles (Theme §11).
///
/// **Apply fonts to symbols:** Use ``Image/init(systemName:)`` (or ``Label``) with `.font(...)` from this module,
/// ``GuardianChromeSize/chromeGlyphFont``, or ``GuardianTypography/font(_:)`` — avoid ad-hoc `resizable()` + fixed
/// frames for standard toolbar and list chrome.
///
/// ### Chrome-aligned glyphs
/// ``GuardianChromeSize/chromeGlyphFont`` matches ``GuardianThemedButton`` / ``GuardianThemedButtonStrip`` label caps
/// and sits inside ``GuardianChromeSize/controlOuterHeight`` rows (28 / 32 / 36 pt).
///
/// ### App shell and dense operator surfaces
/// Sidebar and Mission / Fleet pickers use dedicated ``GuardianTypography/Role`` entries — prefer those roles over
/// duplicating point sizes.
///
/// ## Domain symbol guidance (Theme §11.2 — editorial, not enforced)
///
/// Keep a **small vocabulary** per surface so glyphs read as system language, not decoration.
///
/// - **Fleet / connectivity:** `link`, `link.badge.plus`, `antenna.radiowaves.left.and.right`, `paperclip`, vehicle
///   silhouettes (`airplane`, `helicopter`), `gearshape` for configuration.
/// - **Mission / timeline:** `map`, `location`, play / pause / stop, `flag`, `clock`, roster / people metaphors,
///   checklist shapes.
///
/// When a neutral control fits, prefer `gearshape`, `slider.horizontal.3`, or `ellipsis` instead of borrowing a
/// domain-specific metaphor from another subsystem.
enum GuardianIconography {

    // MARK: - Dense lists and cards

    /// Leading accessory on ~28 pt chrome rows (fleet cards, panel kickers) — 14 pt semibold.
    static var denseRowLeadingGlyph: Font { GuardianTypography.font(.sectionHeadingSemibold) }

    // MARK: - App shell

    /// Root sidebar section icons — 16 pt collapsed strip, 14 pt expanded.
    static func appSidebarSystemGlyph(collapsed: Bool) -> Font {
        GuardianTypography.font(collapsed ? .appSidebarIconCollapsed : .appSidebarIconExpanded)
    }

    // MARK: - Hero pickers and HUD

    static var heroPickerGlyph18: Font { GuardianTypography.font(.heroGlyph18Medium) }
    static var heroGlyph28: Font { GuardianTypography.font(.heroGlyph28Medium) }
    static var heroGlyph30: Font { GuardianTypography.font(.heroGlyph30Medium) }

    // MARK: - Catalog / marketing tiles

    /// Freestanding showcase symbols in the Theme plugin vocabulary grid (16 pt semibold).
    static var catalogSampleGlyph: Font { GuardianTypography.font(.windowHeading16Semibold) }
}
