import SwiftUI

// MARK: - Chart series ramps (Theme §13.1)

/// Multi-series line, area, scatter, and legend accents for telemetry-heavy UI.
///
/// **Indexing:** Use ``seriesColor(at:colorblindSafe:)`` with `index % seriesRampCount` so palettes cycle predictably.
/// **Accessibility:** Offer the colorblind-safe ramp (second set) when users opt in or when defaults are ambiguous; still
/// prefer **distinct line weights / dash patterns / symbols** for redundant encoding beyond color alone.
///
/// **Domain exceptions:** Map route hues may follow mission-local rules (e.g. golden-angle progression) — keep those
/// separate from this catalog ramp so map semantics stay stable.
///
/// **Swift Charts:** Use ``GuardianSwiftChartsTheme`` — `import Charts`, then ``View/guardianChartTheme(colorScheme:)``
/// and ``View/guardianChartSeriesForegroundScale(colorblindSafe:)`` with ``seriesDomainLabels`` /
/// ``seriesForegroundRange(colorblindSafe:)`` for `foregroundStyle(by:)` series keys.
enum GuardianChartPalette {

    /// Default ramp — saturated hues pairwise separated on both light and dark chart backgrounds.
    static let seriesAccentColors: [Color] = [
        Color(red: 0.12, green: 0.45, blue: 0.95),
        Color(red: 0.95, green: 0.45, blue: 0.08),
        Color(red: 0.10, green: 0.68, blue: 0.62),
        Color(red: 0.58, green: 0.22, blue: 0.75),
        Color(red: 0.85, green: 0.20, blue: 0.45),
        Color(red: 0.22, green: 0.58, blue: 0.28),
    ]

    /// Alternate ramp — blue / orange / sky / purple / gold / rose (Wong-style separation; avoids red–green-only pairs).
    static let seriesAccentColorsColorblindSafe: [Color] = [
        Color(red: 0.00, green: 0.45, blue: 0.70),
        Color(red: 0.90, green: 0.35, blue: 0.00),
        Color(red: 0.35, green: 0.70, blue: 0.90),
        Color(red: 0.55, green: 0.35, blue: 0.65),
        Color(red: 0.75, green: 0.55, blue: 0.00),
        Color(red: 0.80, green: 0.40, blue: 0.40),
    ]

    static var seriesRampCount: Int { seriesAccentColors.count }

    static func seriesColor(at index: Int, colorblindSafe: Bool = false) -> Color {
        let palette = colorblindSafe ? seriesAccentColorsColorblindSafe : seriesAccentColors
        guard !palette.isEmpty else { return .accentColor }
        let n = palette.count
        let i = ((index % n) + n) % n
        return palette[i]
    }
}

// MARK: - Gauge and threshold bands (Theme §13.2)

/// Explicit **in-range** (good) fills and strokes for gauges, battery arcs, and horizontal limit bars.
///
/// **Policy:** Always paint a positive “good” band with ``goodBandFill`` / ``goodBandStroke`` — do not rely on the
/// absence of warning color alone. **Caution** and **critical** intentionally track ``GuardianSemanticColors`` warning
/// and danger **stroke** families so thresholds read the same as toasts and inline notices.
enum GuardianGaugeThresholds {

    /// Healthy / in-spec interior for rings and bars (teal-green, legible on ``GuardianThemePalette/backgroundBase``).
    static let goodBandFill = Color(red: 0.08, green: 0.52, blue: 0.42).opacity(0.38)
    /// Edge emphasis for the good band on neutral chart backgrounds.
    static let goodBandStroke = Color(red: 0.05, green: 0.62, blue: 0.48)

    /// Near-limit band — same intent as ``GuardianSemanticColors/warningStroke``.
    static let cautionFill = GuardianSemanticColors.warningStroke.opacity(0.20)
    static let cautionStroke = GuardianSemanticColors.warningStroke

    /// Out-of-spec / hazard — aligned with ``GuardianSemanticColors/dangerStroke``.
    static let criticalFill = GuardianSemanticColors.dangerStroke.opacity(0.22)
    static let criticalStroke = GuardianSemanticColors.dangerStroke
}
