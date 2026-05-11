import SwiftUI

// MARK: - Card chrome (default inset card: raised surface + subtle border)

private struct GuardianInsetCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = GuardianTheme.palette(for: colorScheme)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    /// Inset card: padded body on ``GuardianThemePalette/backgroundRaised`` with ``borderSubtle`` hairline (same rail as modals / sidebars).
    /// Prefer ``GuardianCard`` for new panels (header/footer/media); keep this for quick legacy panels.
    func guardianInsetCard(cornerRadius: CGFloat = 10, padding: CGFloat = GuardianSpacing.cardBodyInset) -> some View {
        modifier(GuardianInsetCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Denser cards (e.g. tight grids): same chrome, smaller padding.
    func guardianInsetCardCompact(cornerRadius: CGFloat = 10, padding: CGFloat = GuardianSpacing.denseGutter) -> some View {
        modifier(GuardianInsetCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Section titles (panel / showcase headers)

/// Uppercased-style section label for long scrolling panels (Theme, long settings).
struct GuardianPanelSectionTitle: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Text(title)
            .font(GuardianTypography.font(.panelSectionTitle))
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Theme accents (badges, buttons, chips — not domain labels)

/// Shared semantic palette for ``GuardianBadge`` and ``GuardianThemedButton``. Use these instead of ad-hoc ``Color`` or per-screen tints.
enum GuardianThemeAccent: Hashable, CaseIterable {
    case primary
    case success
    case warning
    case info
    case danger
    case neutral
    case secondary
    case teal
    case purple
    case pink
    case yellow
}

/// Solid fill vs hairline outline — maps to badge “paint” and button surface.
enum GuardianChromeSurface: Hashable {
    case solid
    case outline
}

/// Control scale for themed buttons (independent of SwiftUI ``ControlSize``).
enum GuardianChromeSize: Hashable, CaseIterable {
    case small
    case medium
    case large

    /// Label / SF Symbol font for ``GuardianThemedButton`` and strip cells at this scale (Theme §11.1 — same cap as the text label).
    var chromeGlyphFont: Font {
        switch self {
        case .small:
            return GuardianTypography.relativeFixed(size: 12, weight: .semibold, relativeTo: .caption)
        case .medium:
            return GuardianTypography.relativeFixed(size: 13, weight: .semibold, relativeTo: .subheadline)
        case .large:
            return GuardianTypography.relativeFixed(size: 14, weight: .semibold, relativeTo: .callout)
        }
    }

    fileprivate var horizontalPadding: CGFloat {
        switch self {
        case .small: 10
        case .medium: 12
        case .large: 14
        }
    }

    fileprivate var verticalPadding: CGFloat {
        switch self {
        case .small: 5
        case .medium: 7
        case .large: 9
        }
    }

    /// Fixed control height for ``GuardianThemedButton`` / strip cells so text, icon-only, and icon+text rows align.
    var controlOuterHeight: CGFloat {
        switch self {
        case .small: 28
        case .medium: 32
        case .large: 36
        }
    }
}

/// Button / badge silhouette: **square** (minimal radius), **cornered** (8pt), **pill** (capsule).
enum GuardianChromeShape: Hashable {
    case square
    case cornered
    case pill
}

// MARK: - Semantic actions (app-wide button conventions)

/// Confirm / save / primary forward action — blue prominent.
struct GuardianPrimaryProminentButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        GuardianThemedButton(title: title, accent: .primary, surface: .solid, size: .small, shape: .cornered, action: action)
    }
}

/// Neutral chrome control (settings-adjacent icon rows, gear, wands) — same geometry as ``GuardianThemedButton`` / ``GuardianPrimaryProminentButton``.
struct GuardianNeutralBorderedButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        GuardianThemedButton(
            accent: .neutral,
            surface: .outline,
            size: .small,
            shape: .cornered,
            contentSizing: .squareToolbarCell,
            action: action,
            label: {
                Image(systemName: systemImage)
            }
        )
        .help(help)
    }
}

/// Delete / cancel row — red prominent with trash (after edit when paired).
struct GuardianDestructiveProminentButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        GuardianThemedButton(title: title, accent: .danger, surface: .solid, size: .small, shape: .cornered, action: action)
    }
}

/// **Edit** (pencil, blue) then **Delete** (trash, red) on one row — matches workspace button rules; same control sizing as other themed buttons.
struct GuardianEditThenDeleteIconRow: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: GuardianSpacing.xs) {
            GuardianThemedButton(
                accent: .primary,
                surface: .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onEdit,
                label: { Image(systemName: "pencil") }
            )
            .help("Edit")

            GuardianThemedButton(
                accent: .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onDelete,
                label: { Image(systemName: "trash") }
            )
            .help("Delete")
        }
    }
}

// MARK: - Badges (accent × paint × size × shape)

/// Solid fill, translucent “light”, or stroked outline (theme badge matrix).
enum GuardianBadgePaint: Hashable {
    case solid
    case light
    case outline
}

enum GuardianBadgeSize: Hashable {
    case small
    case medium
    case large

    fileprivate var font: Font {
        switch self {
        case .small:
            return GuardianTypography.relativeFixed(size: 9, weight: .heavy, relativeTo: .caption2)
        case .medium:
            return GuardianTypography.relativeFixed(size: 10, weight: .semibold, relativeTo: .caption2)
        case .large:
            return GuardianTypography.relativeFixed(size: 11, weight: .semibold, relativeTo: .caption2)
        }
    }

    fileprivate var horizontalPadding: CGFloat {
        switch self {
        case .small: 6
        case .medium: 9
        case .large: 11
        }
    }

    fileprivate var verticalPadding: CGFloat {
        switch self {
        case .small: 3
        case .medium: 4
        case .large: 5
        }
    }
}

/// Badge silhouette: **pill** (capsule), **cornered** (chip), **square** (rounded rect), **circle** (count dot).
enum GuardianBadgeShape: Hashable {
    case pill
    case cornered
    case square
    case circle
}

/// Single-line label badge — use for counts, states, and filter chips.
struct GuardianBadge: View {
    let text: String
    let accent: GuardianThemeAccent
    var paint: GuardianBadgePaint = .solid
    var size: GuardianBadgeSize = .medium
    var shape: GuardianBadgeShape = .pill

    init(
        text: String,
        accent: GuardianThemeAccent,
        paint: GuardianBadgePaint = .solid,
        size: GuardianBadgeSize = .medium,
        shape: GuardianBadgeShape = .pill
    ) {
        self.text = text
        self.accent = accent
        self.paint = paint
        self.size = size
        self.shape = shape
    }

    /// Legacy parameter label — same as ``accent``.
    init(
        text: String,
        tone: GuardianThemeAccent,
        paint: GuardianBadgePaint = .solid,
        size: GuardianBadgeSize = .medium,
        shape: GuardianBadgeShape = .pill
    ) {
        self.init(text: text, accent: tone, paint: paint, size: size, shape: shape)
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GuardianThemeAccentStyle.badgeResolve(
            accent: accent,
            paint: paint,
            colorScheme: colorScheme
        )
        let label = Text(text)
            .font(size.font)
            .foregroundStyle(palette.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)

        let outlineWidth: CGFloat = paint == .outline ? 1.5 : 0

        switch shape {
        case .pill:
            label
                .background(paint == .outline ? Color.clear : palette.fill)
                .clipShape(Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(palette.stroke, lineWidth: outlineWidth))
        case .cornered:
            label
                .background(paint == .outline ? Color.clear : palette.fill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.stroke, lineWidth: outlineWidth)
                )
        case .circle:
            label
                .frame(minWidth: circleMinDimension, minHeight: circleMinDimension)
                .background(paint == .outline ? Color.clear : palette.fill)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(palette.stroke, lineWidth: outlineWidth))
        case .square:
            label
                .frame(minWidth: squareMinDimension, minHeight: squareMinDimension)
                .background(paint == .outline ? Color.clear : palette.fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.stroke, lineWidth: outlineWidth)
                )
        }
    }

    private var circleMinDimension: CGFloat {
        switch size {
        case .small: 20
        case .medium: 22
        case .large: 26
        }
    }

    private var squareMinDimension: CGFloat {
        circleMinDimension
    }
}

// MARK: - Themed button (accent × surface × size × shape)

/// Width grows with the label; height matches the theme control row (``GuardianChromeSize/controlOuterHeight``).
enum GuardianThemedButtonContentSizing: Hashable {
    case intrinsic
    /// Fixed square footprint (width = height) for icon-only controls aligned with text buttons in the same row.
    case squareToolbarCell
}

/// Primary building block for tinted actions — solid or outline, with explicit geometry tokens. Use for **text**, **icon**, or ``Label`` so rows stay aligned.
struct GuardianThemedButton<Label: View>: View {
    var accent: GuardianThemeAccent = .primary
    var surface: GuardianChromeSurface = .solid
    var size: GuardianChromeSize = .small
    var shape: GuardianChromeShape = .cornered
    var isEnabled: Bool = true
    var contentSizing: GuardianThemedButtonContentSizing = .intrinsic
    let action: () -> Void
    private let label: () -> Label

    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: GuardianThemeAccent = .primary,
        surface: GuardianChromeSurface = .solid,
        size: GuardianChromeSize = .small,
        shape: GuardianChromeShape = .cornered,
        isEnabled: Bool = true,
        contentSizing: GuardianThemedButtonContentSizing = .intrinsic,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.accent = accent
        self.surface = surface
        self.size = size
        self.shape = shape
        self.isEnabled = isEnabled
        self.contentSizing = contentSizing
        self.action = action
        self.label = label
    }

    var body: some View {
        let style = GuardianThemeAccentStyle.buttonResolve(
            accent: accent,
            surface: surface,
            colorScheme: colorScheme
        )
        Button(action: action) {
            chromeOuterLabel(style: style, shape: shape)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func chromeOuterLabel(style: GuardianThemeAccentStyle.ButtonResolved, shape: GuardianChromeShape) -> some View {
        let outlineWidth: CGFloat = surface == .outline ? 1.5 : 0
        switch shape {
        case .square:
            chromeRounded(style: style, cornerRadius: 4, outlineWidth: outlineWidth)
        case .cornered:
            chromeRounded(style: style, cornerRadius: 8, outlineWidth: outlineWidth)
        case .pill:
            chromePill(style: style, outlineWidth: outlineWidth)
        }
    }

    private func chromeRounded(style: GuardianThemeAccentStyle.ButtonResolved, cornerRadius: CGFloat, outlineWidth: CGFloat) -> some View {
        let r = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return themedLabelCore(style: style)
            .clipShape(r)
            .overlay(r.strokeBorder(style.stroke, lineWidth: outlineWidth).allowsHitTesting(false))
            .contentShape(r)
    }

    private func chromePill(style: GuardianThemeAccentStyle.ButtonResolved, outlineWidth: CGFloat) -> some View {
        let c = Capsule(style: .continuous)
        return themedLabelCore(style: style)
            .clipShape(c)
            .overlay(c.strokeBorder(style.stroke, lineWidth: outlineWidth).allowsHitTesting(false))
            .contentShape(c)
    }

    private func themedLabelCore(style: GuardianThemeAccentStyle.ButtonResolved) -> some View {
        let dim = isEnabled ? 1.0 : 0.45
        let hPad: CGFloat = contentSizing == .squareToolbarCell ? 0 : size.horizontalPadding
        // Outline surfaces use a clear background — taps would fall through except on glyph bounds.
        // Hit testing for the full control is defined on the clipped label (see ``body`` `contentShape`).
        return label()
            .font(size.chromeGlyphFont)
            .foregroundStyle(style.foreground.opacity(dim))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .padding(.horizontal, hPad)
            .frame(width: contentSizing == .squareToolbarCell ? size.controlOuterHeight : nil)
            .frame(height: size.controlOuterHeight)
            .background(surface == .solid ? style.fill.opacity(dim) : Color.clear)
    }
}

extension GuardianThemedButton where Label == Text {
    init(
        title: String,
        accent: GuardianThemeAccent = .primary,
        surface: GuardianChromeSurface = .solid,
        size: GuardianChromeSize = .small,
        shape: GuardianChromeShape = .cornered,
        isEnabled: Bool = true,
        contentSizing: GuardianThemedButtonContentSizing = .intrinsic,
        action: @escaping () -> Void
    ) {
        self.init(
            accent: accent,
            surface: surface,
            size: size,
            shape: shape,
            isEnabled: isEnabled,
            contentSizing: contentSizing,
            action: action,
            label: { Text(title) }
        )
    }
}

/// Adjacent actions in one bordered control — outline or shared solid fill (toolbar “button group”).
struct GuardianThemedButtonStrip: View {
    var accent: GuardianThemeAccent = .primary
    var surface: GuardianChromeSurface = .outline
    var size: GuardianChromeSize = .small
    var shape: GuardianChromeShape = .cornered
    let items: [(title: String, action: () -> Void)]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = GuardianThemeAccentStyle.buttonResolve(
            accent: accent,
            surface: surface,
            colorScheme: colorScheme
        )
        let corner = stripCornerRadius
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(GuardianTheme.palette(for: colorScheme).borderSubtle)
                        .frame(width: 1)
                        .padding(.vertical, GuardianSpacing.xxs)
                }
                Button(action: item.action) {
                    Text(item.title)
                        .font(size.chromeGlyphFont)
                        .foregroundStyle(style.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, size.horizontalPadding)
                        .frame(maxWidth: .infinity)
                        .frame(height: size.controlOuterHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .background(surface == .solid ? style.fill : Color.clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(style.stroke, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
    }

    private var stripCornerRadius: CGFloat {
        switch shape {
        case .square: 4
        case .cornered: 8
        case .pill: 10
        }
    }
}

// MARK: - Accent resolution (badges + buttons)

private enum GuardianThemeAccentStyle {
    struct BadgeResolved {
        let fill: Color
        let stroke: Color
        let foreground: Color
    }

    struct ButtonResolved {
        let fill: Color
        let stroke: Color
        let foreground: Color
    }

    static func badgeResolve(accent: GuardianThemeAccent, paint: GuardianBadgePaint, colorScheme: ColorScheme) -> BadgeResolved {
        let theme = GuardianTheme.palette(for: colorScheme)
        let accentColor = coreAccent(accent: accent, theme: theme)

        switch paint {
        case .solid:
            return BadgeResolved(
                fill: solidFill(accent: accent, colorScheme: colorScheme),
                stroke: .clear,
                foreground: solidForeground(accent: accent, colorScheme: colorScheme)
            )
        case .light:
            return BadgeResolved(
                fill: accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16),
                stroke: .clear,
                foreground: accentColor
            )
        case .outline:
            return BadgeResolved(fill: .clear, stroke: accentColor, foreground: accentColor)
        }
    }

    static func buttonResolve(accent: GuardianThemeAccent, surface: GuardianChromeSurface, colorScheme: ColorScheme) -> ButtonResolved {
        let theme = GuardianTheme.palette(for: colorScheme)
        let accentColor = coreAccent(accent: accent, theme: theme)
        switch surface {
        case .solid:
            return ButtonResolved(
                fill: solidFill(accent: accent, colorScheme: colorScheme),
                stroke: .clear,
                foreground: solidForeground(accent: accent, colorScheme: colorScheme)
            )
        case .outline:
            if accent == .neutral {
                return ButtonResolved(
                    fill: .clear,
                    stroke: theme.borderSubtle,
                    foreground: theme.textPrimary
                )
            }
            return ButtonResolved(fill: .clear, stroke: accentColor, foreground: accentColor)
        }
    }

    private static func coreAccent(accent: GuardianThemeAccent, theme: GuardianThemePalette) -> Color {
        switch accent {
        case .primary:
            return Color.blue
        case .success:
            return GuardianSemanticColors.successStroke
        case .warning:
            return GuardianSemanticColors.warningStroke
        case .info:
            return GuardianSemanticColors.infoForeground
        case .danger:
            return GuardianSemanticColors.dangerForeground
        case .neutral:
            return theme.textTertiary
        case .secondary:
            return theme.textSecondary
        case .teal:
            return Color(red: 0.12, green: 0.62, blue: 0.58)
        case .purple:
            return GuardianBrand.purple
        case .pink:
            return Color(red: 0.92, green: 0.28, blue: 0.52)
        case .yellow:
            return Color(red: 0.85, green: 0.72, blue: 0.08)
        }
    }

    private static func solidFill(accent: GuardianThemeAccent, colorScheme: ColorScheme) -> Color {
        switch accent {
        case .primary:
            return Color.blue.opacity(0.82)
        case .success:
            return Color.green.opacity(0.72)
        case .warning:
            return Color(red: 0.96, green: 0.72, blue: 0.18)
        case .info:
            return Color.blue.opacity(0.78)
        case .danger:
            return Color.red.opacity(0.78)
        case .neutral:
            return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        case .secondary:
            return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1)
        case .teal:
            return Color(red: 0.10, green: 0.48, blue: 0.45).opacity(0.88)
        case .purple:
            return GuardianBrand.purple.opacity(0.88)
        case .pink:
            return Color(red: 0.78, green: 0.18, blue: 0.42).opacity(0.85)
        case .yellow:
            return Color(red: 0.96, green: 0.82, blue: 0.22)
        }
    }

    private static func solidForeground(accent: GuardianThemeAccent, colorScheme: ColorScheme) -> Color {
        switch accent {
        case .primary, .success, .info, .danger, .teal, .purple, .pink:
            return .white
        case .warning, .yellow:
            return GuardianSemanticColors.warningForeground
        case .neutral, .secondary:
            return GuardianTheme.palette(for: colorScheme).textPrimary
        }
    }
}

/// Legacy alias — new code should use ``GuardianThemeAccent``.
typealias GuardianBadgeTone = GuardianThemeAccent

// MARK: - Settings-style disclosure row (non-navigating)

/// Title + optional value + chevron — use inside cards or forms (not ``NavigationLink``). Same layout as ``GuardianSettingsRow`` without a leading icon.
struct GuardianDisclosureSettingRow: View {
    let title: String
    var value: String?
    let action: () -> Void

    var body: some View {
        GuardianSettingsRow(title: title, systemImage: nil, value: value, action: action)
    }
}

// MARK: - Breadcrumb trail

struct GuardianBreadcrumbTrail: View {
    let segments: [String]

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(spacing: GuardianSpacing.xxs) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(GuardianTypography.font(.breadcrumbSeparator))
                        .foregroundStyle(theme.textTertiary)
                }
                Text(segment)
                    .font(GuardianTypography.font(.breadcrumbSegment(isCurrent: index == segments.count - 1)))
                    .foregroundStyle(index == segments.count - 1 ? theme.textPrimary : theme.textTertiary)
            }
        }
    }
}

// MARK: - Labeled form field (stacked label + control)

/// Stacked **label**, optional **subtitle**, **control** slot, optional **error** line (Theme §6.1). Validation routing: ``GuardianFormKit`` header doc.
struct GuardianLabeledFormField<Content: View>: View {
    let label: String
    var subtitle: String? = nil
    var error: String? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(label)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            if let error, !error.isEmpty {
                Text(error)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(GuardianSemanticColors.dangerForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Search field (toolbar / inspector)

/// Magnifier + field on a raised pill — use for filter bars and pickers instead of raw ``TextField`` on the window base.
struct GuardianSearchBarField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(spacing: GuardianSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(GuardianTypography.font(.searchFieldIcon))
                .foregroundStyle(theme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(GuardianTypography.font(.searchField))
                .foregroundStyle(theme.textPrimary)
                .frame(minHeight: GuardianFormLayout.compactFieldOuterHeight, alignment: .center)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.chromeTightInset)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Metric tile (dashboard / KPI row)

/// Compact stat cell: eyebrow label, emphasized value, optional footnote.
struct GuardianMetricTile: View {
    let title: String
    let value: String
    var caption: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(title.uppercased())
                .font(GuardianTypography.font(.metricEyebrow))
                .foregroundStyle(theme.textTertiary)
                .tracking(0.4)
            Text(value)
                .font(GuardianTypography.font(.metricValue))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(GuardianTypography.font(.metricCaption))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Elevated strip (sub-bars, compact toolbars)

/// Full-width strip on ``GuardianThemePalette/backgroundRaised`` with the same corner + border language as Fleet / MC sub-bars.
struct GuardianElevatedStrip<Content: View>: View {
    var horizontalPadding: CGFloat = GuardianSpacing.sm
    var verticalPadding: CGFloat = GuardianSpacing.xs
    var cornerRadius: CGFloat = 8
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
    }
}
