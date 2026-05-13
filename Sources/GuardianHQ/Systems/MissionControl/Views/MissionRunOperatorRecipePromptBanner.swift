import SwiftUI

/// MC-R bottom operator prompts for recipe escalations raised by MRE (headless recipe runs).
/// Host registration + lists are owned by ``OperatorPromptCenter``.
///
/// Visual shell matches ``GuardianBottomPromptBanner`` **mission-control docked** strips (flush to the
/// content column’s leading/trailing/bottom — the host already sits right of the nav sidebar): full width,
/// top hairline, no floating rounded card.
struct MissionRunOperatorRecipePromptBanner: View {
    let missionRunID: UUID

    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter

    private var prompts: [OperatorPromptEvent] {
        operatorPromptCenter.activeMCRPrompts(forMissionRunID: missionRunID)
    }

    var body: some View {
        Group {
            if !prompts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(Color.white.opacity(0.12))
                        }
                        MissionRunOperatorRecipePromptCard(
                            event: event,
                            onSelectOption: { option in
                                let answer = OperatorPromptAnswer(
                                    promptID: event.id,
                                    selectedOptionID: option.id,
                                    verb: option.verb,
                                    remember: false,
                                    resolution: .operatorChose
                                )
                                _ = operatorPromptCenter.submitAnswer(answer)
                            }
                        )
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(GuardianMotion.feedbackCrossfade, value: prompts.map(\.id))
        .allowsHitTesting(!prompts.isEmpty)
        .onAppear {
            operatorPromptCenter.setMCRPromptPanelHostActive(true, missionRunID: missionRunID)
        }
        .onDisappear {
            operatorPromptCenter.setMCRPromptPanelHostActive(false, missionRunID: missionRunID)
        }
    }
}

// MARK: - Card

struct MissionRunOperatorRecipePromptCard: View {
    let event: OperatorPromptEvent
    let onSelectOption: (OperatorPromptOption) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var cardFill: Color {
        event.displaySource.resolvedOperatorPromptCardFillColor(severityForAssistantHexFallback: event.severity)
    }

    private var onPastelIssuerFill: Bool {
        event.displaySource.usesPastelIssuerOperatorPromptCardFill
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            dockedFourColumnRow
                .frame(minWidth: 780)
            dockedCompactStacked
        }
        .modifier(MissionRunOperatorRecipePromptExpiryModifier(event: event))
        .padding(.horizontal, GuardianSpacing.cardBodyInset)
        .padding(.vertical, GuardianSpacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardFill)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(onPastelIssuerFill ? theme.borderSubtle : Color.white.opacity(0.2)),
            alignment: .top
        )
    }

    // MARK: Wide layout (HStack — four blocks)

    private var dockedFourColumnRow: some View {
        HStack(alignment: .top, spacing: GuardianSpacing.md) {
            sourceGlyphBlock
                .frame(width: 104, alignment: .center)

            titleAndDescriptionBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

            contextFactsBlock
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 300, alignment: .leading)
                .layoutPriority(1)

            HStack {
                Spacer(minLength: 0)
                OperatorRecipePromptOptionGrid(
                    options: event.effectiveOptions,
                    neutralOutlineTint: onPastelIssuerFill ? theme.textSecondary : Color.white,
                    dangerOutlineTint: onPastelIssuerFill ? GuardianSemanticColors.dangerStroke : Color.white,
                    onSelect: onSelectOption
                )
                .frame(maxWidth: 320, alignment: .trailing)
            }
            .frame(minWidth: 200, alignment: .trailing)
        }
    }

    // MARK: Compact layout (narrow host)

    private var dockedCompactStacked: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(alignment: .top, spacing: GuardianSpacing.md) {
                sourceGlyphBlock
                    .frame(width: 104, alignment: .center)
                titleAndDescriptionBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            contextFactsBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            OperatorRecipePromptOptionGrid(
                options: event.effectiveOptions,
                neutralOutlineTint: onPastelIssuerFill ? theme.textSecondary : Color.white,
                dangerOutlineTint: onPastelIssuerFill ? GuardianSemanticColors.dangerStroke : Color.white,
                onSelect: onSelectOption
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Blocks

    private var sourceGlyphBlock: some View {
        VStack(spacing: GuardianSpacing.xsTight) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sourceGlyphPlateFill)
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(severityAccentColor)
            }
            Text(event.displaySource.operatorFacingShortLabel)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(sourceCaptionForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source \(event.displaySource.operatorFacingShortLabel)")
    }

    private var sourceGlyphPlateFill: Color {
        if onPastelIssuerFill {
            return theme.backgroundElevated.opacity(0.55)
        }
        return Color.white.opacity(0.14)
    }

    private var sourceCaptionForeground: Color {
        onPastelIssuerFill ? theme.textSecondary : Color.white.opacity(0.88)
    }

    private var severityAccentColor: Color {
        operatorPromptSeverityIconColor(event.severity)
    }

    private var titleAndDescriptionBlock: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(event.title)
                .font(GuardianTypography.font(.bottomPromptMessage))
                .foregroundStyle(onPastelIssuerFill ? theme.textPrimary : Color.white)
            if !event.body.isEmpty {
                Text(event.body)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(onPastelIssuerFill ? theme.textSecondary : Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var contextFactsBlock: some View {
        if event.contextFacts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(event.contextFacts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xsTight) {
                        Text(fact.label + ":")
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(onPastelIssuerFill ? theme.textTertiary : Color.white.opacity(0.75))
                        Text(fact.value)
                            .font(GuardianTypography.font(.denseCaption10Regular))
                            .foregroundStyle(onPastelIssuerFill ? theme.textSecondary : Color.white.opacity(0.9))
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func operatorPromptSeverityIconColor(_ severity: GuardianFeedbackSeverity) -> Color {
        switch severity {
        case .success: return GuardianSemanticColors.successStroke
        case .info: return GuardianSemanticColors.infoForeground
        case .warning: return GuardianSemanticColors.warningStroke
        case .error: return GuardianSemanticColors.dangerStroke
        }
    }
}

// MARK: - Option grid

private struct OperatorRecipePromptOptionGrid: View {
    let options: [OperatorPromptOption]
    let neutralOutlineTint: Color
    let dangerOutlineTint: Color
    let onSelect: (OperatorPromptOption) -> Void

    private var columns: [GridItem] {
        switch options.count {
        case 0:
            return []
        case 1:
            return [GridItem(.flexible())]
        default:
            return [
                GridItem(.flexible(), spacing: GuardianSpacing.xs),
                GridItem(.flexible(), spacing: GuardianSpacing.xs),
            ]
        }
    }

    var body: some View {
        Group {
            if options.isEmpty {
                EmptyView()
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(options, id: \.id) { option in
                        optionButton(option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ option: OperatorPromptOption) -> some View {
        switch option.role {
        case .confirm:
            GuardianPrimaryProminentButton(title: option.humanLabel) {
                onSelect(option)
            }
            .guardianPointerOnHover()
        case .neutral:
            GuardianThemedButton(
                title: option.humanLabel,
                accent: .neutral,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: { onSelect(option) }
            )
            .tint(neutralOutlineTint)
            .guardianPointerOnHover()
        case .cancel:
            GuardianThemedButton(
                title: option.humanLabel,
                accent: .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: { onSelect(option) }
            )
            .tint(dangerOutlineTint)
            .guardianPointerOnHover()
        }
    }
}

// MARK: - Expiry

private struct MissionRunOperatorRecipePromptExpiryModifier: ViewModifier {
    let event: OperatorPromptEvent

    func body(content: Content) -> some View {
        content.task(id: event.id) {
            let delay = event.expiresAt.timeIntervalSinceNow
            if delay > 0 {
                let ns = UInt64(min(delay, 24 * 3600) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            await MainActor.run {
                OperatorPromptCenter.shared.resolveExpiry(for: event)
            }
        }
    }
}
