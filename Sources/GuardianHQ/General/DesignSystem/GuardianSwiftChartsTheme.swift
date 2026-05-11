import Charts
import SwiftUI

// MARK: - Swift Charts integration (Theme §13)

/// Guardian defaults for **Swift Charts** (`import Charts`): plot chrome, axis marks, and optional **series → color**
/// scales aligned with ``GuardianChartPalette``.
///
/// **Usage:** Build your ``Chart`` as usual, then apply ``View/guardianChartTheme(colorScheme:)``. For multi-series lines
/// or bars, pair ``foregroundStyle(by:)`` with ``chartForegroundStyleScale(domain:range:)`` using
/// ``GuardianChartPalette/seriesDomainLabels`` and ``GuardianChartPalette/seriesForegroundRange(colorblindSafe:)``.
///
/// **Accessibility:** Keep dash / symbol / line-width variation in addition to color; the colorblind-safe ramp is a
/// second parallel range, not an automatic substitution.
enum GuardianSwiftChartsTheme {

    /// Plot area fill behind marks (inside axes).
    static func plotBackground(for colorScheme: ColorScheme) -> Color {
        let p = GuardianTheme.palette(for: colorScheme)
        return p.backgroundRaised.opacity(0.42)
    }
}

extension View {

    /// Applies Guardian plot background and axis styling so ``Chart`` matches ``GuardianThemePalette`` in light and dark.
    func guardianChartTheme(colorScheme: ColorScheme) -> some View {
        let palette = GuardianTheme.palette(for: colorScheme)
        return self
            .chartPlotStyle { plot in
                plot.background(GuardianSwiftChartsTheme.plotBackground(for: colorScheme))
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(palette.borderSubtle.opacity(0.85))
                    AxisTick()
                        .foregroundStyle(palette.borderSubtle)
                    AxisValueLabel()
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(palette.borderSubtle.opacity(0.85))
                    AxisTick()
                        .foregroundStyle(palette.borderSubtle)
                    AxisValueLabel()
                        .foregroundStyle(palette.textTertiary)
                }
            }
    }

    /// Maps ``GuardianChartPalette/seriesDomainLabels`` to the default or colorblind-safe ramp for ``foregroundStyle(by:)`` channels.
    func guardianChartSeriesForegroundScale(colorblindSafe: Bool = false) -> some View {
        chartForegroundStyleScale(
            domain: GuardianChartPalette.seriesDomainLabels,
            range: GuardianChartPalette.seriesForegroundRange(colorblindSafe: colorblindSafe)
        )
    }
}

extension GuardianChartPalette {

    /// Stable legend / `foregroundStyle(by:)` category strings (one per ramp slot). Keep ordering aligned with ``seriesAccentColors``.
    static let seriesDomainLabels: [String] = [
        "Series 1", "Series 2", "Series 3", "Series 4", "Series 5", "Series 6",
    ]

    /// Colors in the same order as ``seriesDomainLabels`` for ``chartForegroundStyleScale(domain:range:)``.
    static func seriesForegroundRange(colorblindSafe: Bool) -> [Color] {
        colorblindSafe ? seriesAccentColorsColorblindSafe : seriesAccentColors
    }

    /// Label for `foregroundStyle(by: .value("Series", …))` when you only have a numeric series index.
    static func seriesDomainLabel(at index: Int) -> String {
        let n = seriesDomainLabels.count
        guard n > 0 else { return "Series" }
        return seriesDomainLabels[((index % n) + n) % n]
    }
}
