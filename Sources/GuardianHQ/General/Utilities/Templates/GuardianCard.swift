import SwiftUI

// MARK: - Layout tokens (single source — Theme docs + new screens)

/// Padding, radius, and rhythm for ``GuardianCard``. Prefer these over ad-hoc card metrics.
enum GuardianCardLayout {
    static let cornerRadius: CGFloat = 10
    static let headerHorizontalPadding: CGFloat = 14
    /// Vertical padding around header **content**; sized with ``headerContentMinHeight`` so a row of
    /// ``GuardianThemedButton`` / ``GuardianChromeSize/small`` (28pt outer height) does not crowd the strip hairlines.
    static let headerVerticalPadding: CGFloat = 12
    static let footerHorizontalPadding: CGFloat = 14
    static let footerVerticalPadding: CGFloat = 12
    static let defaultBodyPadding: CGFloat = 14

    /// Minimum height of header **content** (inside horizontal padding, before vertical padding) so toolbar-style
    /// rows align with ``GuardianThemedButton`` small geometry (28pt control height).
    static let headerContentMinHeight: CGFloat = 28
    /// Same idea as ``headerContentMinHeight`` for footer strips (actions, status rows).
    static let footerContentMinHeight: CGFloat = 28
}

// MARK: - Border

/// Hairline around ``GuardianCard``. Resolved with ``GuardianTheme`` / ``GuardianSemanticColors``.
enum GuardianCardBorder: Hashable, Sendable {
    case none
    case subtle
    case primary
    case danger
    case warning

    func strokeColor(for colorScheme: ColorScheme) -> Color? {
        let theme = GuardianTheme.palette(for: colorScheme)
        switch self {
        case .none:
            return nil
        case .subtle:
            return theme.borderSubtle
        case .primary:
            return GuardianSemanticColors.infoForeground
        case .danger:
            return GuardianSemanticColors.dangerStroke
        case .warning:
            return GuardianSemanticColors.warningStroke
        }
    }
}

// MARK: - Sections

/// Which slots ``GuardianCard`` renders.
///
/// Include ``body`` for typical cards, or use ``media`` alone for a full-bleed media-only shell (see ``GuardianCard`` assertion).
struct GuardianCardSections: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    static let media = GuardianCardSections(rawValue: 1 << 0)
    static let header = GuardianCardSections(rawValue: 1 << 1)
    static let body = GuardianCardSections(rawValue: 1 << 2)
    static let footer = GuardianCardSections(rawValue: 1 << 3)

    /// Body only — default card.
    static let bodyOnly: GuardianCardSections = [.body]

    /// Media fills the card; bottom corners match the outer card radius (no header/body/footer).
    static let mediaOnly: GuardianCardSections = [.media]
}

// MARK: - Configuration

/// Tunable chrome for ``GuardianCard`` without growing the primary initializer surface.
struct GuardianCardConfiguration: Hashable, Sendable {
    var border: GuardianCardBorder = .subtle
    var cornerRadius: CGFloat = GuardianCardLayout.cornerRadius
    /// Padding applied around the **body** slot only (use `0` for edge-to-edge map / media-style bodies).
    var bodyPadding: CGFloat = GuardianCardLayout.defaultBodyPadding

    static let standard = GuardianCardConfiguration()
}

// MARK: - Hairline between slots

private struct GuardianCardHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Card

/// Bootstrap-style **card**: optional **media** (flush, full width), **header**, **body**, **footer**,
/// with a theme-aware outer stroke and hairlines between populated slots.
///
/// **Header / footer strips:** Default layout uses a minimum content height aligned with small
/// ``GuardianThemedButton`` rows plus ``GuardianCardLayout/headerVerticalPadding`` so toolbar-style headers are not tight against the hairline.
///
/// **Media corners:** The **media** slot is a full-width rectangle; the card’s outer ``RoundedRectangle`` clip rounds the
/// overall shell (top corners when media is first, all four on media-only cards). The seam to header/body/footer is a
/// straight horizontal edge—no per-slot corner mask, which avoids double-clipping and radius mismatches with children.
///
/// **Naming:** This is the standard **panel card** chrome (raised surface). It is unrelated to the main nav **sidebar**
/// and unrelated to the trailing ``AppDrawer`` shell.
struct GuardianCard<Media: View, Header: View, BodyContent: View, Footer: View>: View {
    private let configuration: GuardianCardConfiguration
    private let sections: GuardianCardSections
    @ViewBuilder private let media: () -> Media
    @ViewBuilder private let header: () -> Header
    @ViewBuilder private let bodyContent: () -> BodyContent
    @ViewBuilder private let footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(
        configuration: GuardianCardConfiguration = .standard,
        sections: GuardianCardSections,
        @ViewBuilder media: @escaping () -> Media,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder body: @escaping () -> BodyContent,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.configuration = configuration
        self.sections = sections
        self.media = media
        self.header = header
        self.bodyContent = body
        self.footer = footer
        assert(
            sections.contains(.body) || sections == .mediaOnly,
            "GuardianCard requires .body in sections, or use sections == .mediaOnly for a media-only card."
        )
    }

    var body: some View {
        let slots = orderedSlots()
        return VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                if index > 0 {
                    GuardianCardHairline()
                }
                slotView(slot)
            }
        }
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous))
        .overlay {
            if let stroke = configuration.border.strokeColor(for: colorScheme) {
                RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
        }
    }

    private enum Slot: Int, CaseIterable {
        case media, header, body, footer
    }

    private func orderedSlots() -> [Slot] {
        var slots: [Slot] = []
        if sections.contains(.media) { slots.append(.media) }
        if sections.contains(.header) { slots.append(.header) }
        if sections.contains(.body) { slots.append(.body) }
        if sections.contains(.footer) { slots.append(.footer) }
        return slots
    }

    @ViewBuilder
    private func slotView(_ slot: Slot) -> some View {
        switch slot {
        case .media:
            media()
                .frame(maxWidth: .infinity)
        case .header:
            header()
                .frame(
                    maxWidth: .infinity,
                    minHeight: GuardianCardLayout.headerContentMinHeight,
                    alignment: .center
                )
                .padding(.horizontal, GuardianCardLayout.headerHorizontalPadding)
                .padding(.vertical, GuardianCardLayout.headerVerticalPadding)
                .background(theme.backgroundElevated)
        case .body:
            bodyContent()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(configuration.bodyPadding)
        case .footer:
            footer()
                .frame(
                    maxWidth: .infinity,
                    minHeight: GuardianCardLayout.footerContentMinHeight,
                    alignment: .center
                )
                .padding(.horizontal, GuardianCardLayout.footerHorizontalPadding)
                .padding(.vertical, GuardianCardLayout.footerVerticalPadding)
                .background(theme.backgroundElevated)
        }
    }
}

// MARK: - Convenience inits (body-only, common stacks)

extension GuardianCard where Media == EmptyView, Header == EmptyView, Footer == EmptyView {
    /// Simple raised card: body only, default border and padding.
    init(
        configuration: GuardianCardConfiguration = .standard,
        @ViewBuilder body: @escaping () -> BodyContent
    ) {
        self.init(
            configuration: configuration,
            sections: .bodyOnly,
            media: { EmptyView() },
            header: { EmptyView() },
            body: body,
            footer: { EmptyView() }
        )
    }
}

extension GuardianCard where Media == EmptyView, Footer == EmptyView {
    /// Card with a header strip + body.
    init(
        configuration: GuardianCardConfiguration = .standard,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder body: @escaping () -> BodyContent
    ) {
        self.init(
            configuration: configuration,
            sections: [.header, .body],
            media: { EmptyView() },
            header: header,
            body: body,
            footer: { EmptyView() }
        )
    }
}

extension GuardianCard where Media == EmptyView, Header == EmptyView {
    /// Card with body + footer strip.
    init(
        configuration: GuardianCardConfiguration = .standard,
        @ViewBuilder body: @escaping () -> BodyContent,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            configuration: configuration,
            sections: [.body, .footer],
            media: { EmptyView() },
            header: { EmptyView() },
            body: body,
            footer: footer
        )
    }
}

extension GuardianCard where Header == EmptyView, Footer == EmptyView {
    /// Media (flush, full width) + body — set `configuration.bodyPadding` to `0` for map-style edge-to-edge bodies.
    init(
        configuration: GuardianCardConfiguration = .standard,
        @ViewBuilder media: @escaping () -> Media,
        @ViewBuilder body: @escaping () -> BodyContent
    ) {
        self.init(
            configuration: configuration,
            sections: [.media, .body],
            media: media,
            header: { EmptyView() },
            body: body,
            footer: { EmptyView() }
        )
    }
}

extension GuardianCard where Header == EmptyView, BodyContent == EmptyView, Footer == EmptyView {
    /// Full-bleed media fills the card; all four corners use the card radius (no following slots).
    init(
        configuration: GuardianCardConfiguration = .standard,
        @ViewBuilder media: @escaping () -> Media
    ) {
        self.init(
            configuration: configuration,
            sections: .mediaOnly,
            media: media,
            header: { EmptyView() },
            body: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}
