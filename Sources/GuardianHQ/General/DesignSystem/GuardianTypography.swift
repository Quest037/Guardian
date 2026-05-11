import SwiftUI

/// Guardian typography: **named scale**, **semantic roles**, and helpers that respect macOS **Accessibility** display sizes.
///
/// **Dynamic Type policy:** Prefer ``Scale`` (maps to ``Font/TextStyle``) so text tracks the user’s content size.
/// ``relativeFixed`` uses fixed point sizes (with a documenting `relativeTo` label) for dense operator caps where the
/// deployment toolchain does not expose scaling `Font.system(size:…relativeTo:)`. Controls that must stay single-line
/// already use ``Text/minimumScaleFactor``; do not clamp with ``environment(\.sizeCategory, ...)`` unless needed.
///
/// **Monospaced copy:** Use ``monospaced(_:weight:)`` or ``relativeFixed(..., design: .monospaced, ...)`` for telemetry
/// tables, MAV/hex identifiers, structured codes, and numeric countdowns. Use proportional fonts for sentences and labels.
enum GuardianTypography {

    // MARK: - Named scale (HIG-aligned → Dynamic Type)

    /// Maps to SwiftUI text styles so sizing follows system accessibility settings.
    enum Scale: CaseIterable, Hashable, Sendable {
        case largeTitle
        case title
        case title2
        case title3
        case headline
        case body
        case callout
        case subheadline
        case footnote
        case caption
        case caption2

        var textStyle: Font.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption: .caption
            case .caption2: .caption2
            }
        }

        func font(weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
            Font.system(textStyle, design: design).weight(weight)
        }
    }

    // MARK: - Semantic roles (operator UI)

    /// Dense, mission-control style roles — not marketing display type.
    enum Role: Hashable, Sendable {
        case operatorBody
        case operatorCaption
        case inspectorLabel
        /// Proportional dense line; use ``logLineMonospaced`` when showing codes / telemetry.
        case logLine
        case logLineMonospaced
        case confirmBody
        case panelSectionTitle
        case inlineNoticeTitle
        case inlineNoticeDetail
        case toastEphemeral
        case bottomPromptMessage
        case bottomPromptIcon
        case breadcrumbSeparator
        case breadcrumbSegment(isCurrent: Bool)
        case disclosureRowTitle
        case disclosureRowValue
        case disclosureChevron
        case formFieldLabel
        case searchField
        case searchFieldIcon
        case metricEyebrow
        case metricValue
        case metricCaption
        case confirmHeaderIconStandard
        case confirmHeaderIconDanger
        case inlineNoticeIconCompactBold
        case inlineNoticeIconWarning
        case inlineNoticeIconDangerHeavy

        // Dense operator surfaces (Mission Control, Live Drive, Missions, Fleet cards)
        case denseCaption10Regular
        case denseCaption10Semibold
        case denseCaption10Medium
        case denseCaption12Regular
        case denseCaption12Medium
        case denseFootnoteRegular
        case denseSubsection13Regular
        case subsectionTitleSemibold
        case sectionHeadingSemibold
        case panelEmphasisTitleBold
        case panelSecondaryHeadingSemibold
        case windowHeading16Semibold
        case windowHeading16Medium
        case heroGlyph18Medium
        case heroGlyph30Medium
        case heroGlyph28Medium
        case mapWaypointMicroHeavy
        case telemetryMono10Semibold
        case telemetryMono10Regular
        case telemetryMono10Medium
        case telemetryMono11Regular
        case telemetryMono11Medium
        case telemetryMono12Semibold
        case telemetryNano9Semibold
        case telemetryMono9Regular
        case telemetryMono9Semibold
        case telemetryMono13Regular
        case telemetryMono11Semibold
        case telemetryMono12Bold
        case telemetryMono14Semibold
        case heroTimer30Bold
        case denseMicro10Heavy
        case hudCountdownRounded22Bold
        case hudTitle16Bold
        case missionProminentGlyph18Semibold
        case missionCardEmphasis13Bold
        case missionMicro10Bold
        case missionRowKicker12Bold

        // App shell
        case appSidebarRowTitle(isSelected: Bool)
        case appSidebarIconCollapsed
        case appSidebarIconExpanded
        case appWindowToolbarTitle
        case appVersionCaption

        // Plugins screen
        case pluginsPageHero
    }

    static func font(_ role: Role) -> Font {
        switch role {
        case .operatorBody:
            return Scale.body.font(weight: .medium)
        case .operatorCaption:
            return Scale.caption.font(weight: .medium)
        case .inspectorLabel:
            return Scale.subheadline.font(weight: .semibold)
        case .logLine:
            return Scale.footnote.font(weight: .medium)
        case .logLineMonospaced:
            return monospaced(.footnote, weight: .medium)
        case .confirmBody:
            return Scale.callout.font(weight: .regular)
        case .panelSectionTitle:
            return relativeFixed(size: 15, weight: .semibold, relativeTo: .headline)
        case .inlineNoticeTitle:
            return relativeFixed(size: 12, weight: .semibold, relativeTo: .caption)
        case .inlineNoticeDetail:
            return relativeFixed(size: 11, weight: .medium, relativeTo: .footnote)
        case .toastEphemeral:
            return relativeFixed(size: 13, weight: .semibold, relativeTo: .subheadline)
        case .bottomPromptMessage:
            return relativeFixed(size: 12, weight: .medium, relativeTo: .caption)
        case .bottomPromptIcon:
            return relativeFixed(size: 14, weight: .semibold, relativeTo: .subheadline)
        case .breadcrumbSeparator:
            return relativeFixed(size: 9, weight: .bold, relativeTo: .caption2)
        case .breadcrumbSegment(let isCurrent):
            return relativeFixed(size: 11, weight: isCurrent ? .semibold : .regular, relativeTo: .footnote)
        case .disclosureRowTitle:
            return relativeFixed(size: 13, weight: .medium, relativeTo: .callout)
        case .disclosureRowValue:
            return relativeFixed(size: 12, weight: .regular, relativeTo: .caption)
        case .disclosureChevron:
            return relativeFixed(size: 10, weight: .semibold, relativeTo: .caption2)
        case .formFieldLabel:
            return relativeFixed(size: 11, weight: .semibold, relativeTo: .caption)
        case .searchField:
            return relativeFixed(size: 12, weight: .regular, relativeTo: .caption)
        case .searchFieldIcon:
            return relativeFixed(size: 12, weight: .semibold, relativeTo: .caption)
        case .metricEyebrow:
            return relativeFixed(size: 9, weight: .bold, relativeTo: .caption2)
        case .metricValue:
            return relativeFixed(size: 18, weight: .bold, design: .rounded, relativeTo: .title3)
        case .metricCaption:
            return relativeFixed(size: 10, weight: .regular, relativeTo: .caption2)
        case .confirmHeaderIconStandard:
            return relativeFixed(size: 18, weight: .semibold, relativeTo: .title3)
        case .confirmHeaderIconDanger:
            return relativeFixed(size: 17, weight: .bold, relativeTo: .title3)
        case .inlineNoticeIconCompactBold:
            return relativeFixed(size: 11, weight: .bold, relativeTo: .caption)
        case .inlineNoticeIconWarning:
            return relativeFixed(size: 15, weight: .semibold, relativeTo: .subheadline)
        case .inlineNoticeIconDangerHeavy:
            return relativeFixed(size: 10, weight: .heavy, relativeTo: .caption2)

        case .denseCaption10Regular:
            return relativeFixed(size: 10, weight: .regular, relativeTo: .caption2)
        case .denseCaption10Semibold:
            return relativeFixed(size: 10, weight: .semibold, relativeTo: .caption2)
        case .denseCaption10Medium:
            return relativeFixed(size: 10, weight: .medium, relativeTo: .caption2)
        case .denseCaption12Regular:
            return relativeFixed(size: 12, weight: .regular, relativeTo: .caption)
        case .denseCaption12Medium:
            return relativeFixed(size: 12, weight: .medium, relativeTo: .caption)
        case .denseFootnoteRegular:
            return relativeFixed(size: 11, weight: .regular, relativeTo: .footnote)
        case .denseSubsection13Regular:
            return relativeFixed(size: 13, weight: .regular, relativeTo: .callout)
        case .subsectionTitleSemibold:
            return relativeFixed(size: 13, weight: .semibold, relativeTo: .subheadline)
        case .sectionHeadingSemibold:
            return relativeFixed(size: 14, weight: .semibold, relativeTo: .subheadline)
        case .panelEmphasisTitleBold:
            return relativeFixed(size: 15, weight: .bold, relativeTo: .headline)
        case .panelSecondaryHeadingSemibold:
            return relativeFixed(size: 15, weight: .semibold, relativeTo: .headline)
        case .windowHeading16Semibold:
            return relativeFixed(size: 16, weight: .semibold, relativeTo: .headline)
        case .windowHeading16Medium:
            return relativeFixed(size: 16, weight: .medium, relativeTo: .headline)
        case .heroGlyph18Medium:
            return relativeFixed(size: 18, weight: .medium, relativeTo: .title3)
        case .heroGlyph30Medium:
            return relativeFixed(size: 30, weight: .medium, relativeTo: .title2)
        case .heroGlyph28Medium:
            return relativeFixed(size: 28, weight: .medium, relativeTo: .title2)
        case .mapWaypointMicroHeavy:
            return relativeFixed(size: 7.5, weight: .heavy, relativeTo: .caption2)
        case .telemetryMono10Semibold:
            return relativeFixed(size: 10, weight: .semibold, design: .monospaced, relativeTo: .caption2)
        case .telemetryMono10Regular:
            return relativeFixed(size: 10, weight: .regular, design: .monospaced, relativeTo: .caption2)
        case .telemetryMono10Medium:
            return relativeFixed(size: 10, weight: .medium, design: .monospaced, relativeTo: .caption2)
        case .telemetryMono11Regular:
            return relativeFixed(size: 11, weight: .regular, design: .monospaced, relativeTo: .footnote)
        case .telemetryMono11Medium:
            return relativeFixed(size: 11, weight: .medium, design: .monospaced, relativeTo: .footnote)
        case .telemetryMono12Semibold:
            return relativeFixed(size: 12, weight: .semibold, design: .monospaced, relativeTo: .caption)
        case .telemetryNano9Semibold:
            return relativeFixed(size: 9, weight: .semibold, relativeTo: .caption2)
        case .telemetryMono9Regular:
            return relativeFixed(size: 9, weight: .regular, design: .monospaced, relativeTo: .caption2)
        case .telemetryMono9Semibold:
            return relativeFixed(size: 9, weight: .semibold, design: .monospaced, relativeTo: .caption2)
        case .telemetryMono13Regular:
            return relativeFixed(size: 13, weight: .regular, design: .monospaced, relativeTo: .callout)
        case .telemetryMono11Semibold:
            return relativeFixed(size: 11, weight: .semibold, design: .monospaced, relativeTo: .footnote)
        case .telemetryMono12Bold:
            return relativeFixed(size: 12, weight: .bold, design: .monospaced, relativeTo: .caption)
        case .telemetryMono14Semibold:
            return relativeFixed(size: 14, weight: .semibold, design: .monospaced, relativeTo: .subheadline)
        case .heroTimer30Bold:
            return relativeFixed(size: 30, weight: .bold, relativeTo: .title2)
        case .denseMicro10Heavy:
            return relativeFixed(size: 10, weight: .heavy, relativeTo: .caption2)
        case .hudCountdownRounded22Bold:
            return relativeFixed(size: 22, weight: .bold, design: .rounded, relativeTo: .title2)
        case .hudTitle16Bold:
            return relativeFixed(size: 16, weight: .bold, relativeTo: .headline)
        case .missionProminentGlyph18Semibold:
            return relativeFixed(size: 18, weight: .semibold, relativeTo: .title3)
        case .missionCardEmphasis13Bold:
            return relativeFixed(size: 13, weight: .bold, relativeTo: .subheadline)
        case .missionMicro10Bold:
            return relativeFixed(size: 10, weight: .bold, relativeTo: .caption2)
        case .missionRowKicker12Bold:
            return relativeFixed(size: 12, weight: .bold, relativeTo: .caption)

        case .appSidebarRowTitle(let isSelected):
            return relativeFixed(size: 14, weight: isSelected ? .semibold : .regular, relativeTo: .subheadline)
        case .appSidebarIconCollapsed:
            return relativeFixed(size: 16, weight: .semibold, relativeTo: .headline)
        case .appSidebarIconExpanded:
            return relativeFixed(size: 14, weight: .semibold, relativeTo: .subheadline)
        case .appWindowToolbarTitle:
            return relativeFixed(size: 15, weight: .bold, relativeTo: .headline)
        case .appVersionCaption:
            return relativeFixed(size: 11, weight: .medium, relativeTo: .footnote)

        case .pluginsPageHero:
            return relativeFixed(size: 22, weight: .bold, relativeTo: .title2)
        }
    }

    /// Recovery / abort acknowledgement copy in compact vs expanded mission live rows.
    static func denseAcknowledgementCaption(compact: Bool) -> Font {
        compact ? font(.denseCaption10Regular) : font(.denseFootnoteRegular)
    }

    /// Monospaced variant of a scale (telemetry, IDs, codes).
    static func monospaced(_ scale: Scale, weight: Font.Weight = .regular) -> Font {
        Font.system(scale.textStyle, design: .monospaced).weight(weight)
    }

    /// Fixed cap size (pt) with explicit weight/design. The `relativeTo` label documents the **intended** Dynamic Type
    /// anchor for future tuning; SwiftUI’s `Font.system(size:…relativeTo:)` is not used here so the package stays
    /// buildable on the current macOS 13 minimum + toolchain.
    static func relativeFixed(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design = .default,
        relativeTo _: Font.TextStyle
    ) -> Font {
        Font.system(size: size, weight: weight, design: design)
    }
}
