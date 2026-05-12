import SwiftUI

// MARK: - Operator prompt inbox (AppDrawer body)

/// Lists pending operator prompts mirrored to ``OperatorPromptDeliveryTarget/inAppInbox`` and
/// resolves them into ``OperatorPromptResumptionChannel``.
struct OperatorPromptInboxDrawerView: View {

    @EnvironmentObject private var center: OperatorPromptCenter
    @EnvironmentObject private var operatorPromptReviewFocus: OperatorPromptReviewFocusController
    @EnvironmentObject private var appDrawer: AppDrawer
    @Environment(\.colorScheme) private var colorScheme

    @State private var rememberByPromptID: [UUID: Bool] = [:]

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// Shown under the drawer title and above any pending decision cards.
    private var decisionsIntroCopy: String {
        "Live missions often need your permission to do things according to the rules and policies you defined when it was set up. You will find them here."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(decisionsIntroCopy)
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GuardianSpacing.md)
                .padding(.top, GuardianSpacing.md)
                .padding(.bottom, GuardianSpacing.sm)

            if center.inboxPrompts.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GuardianSpacing.md) {
                        ForEach(center.inboxPrompts) { event in
                            promptCard(event)
                        }
                    }
                    .padding(.horizontal, GuardianSpacing.md)
                    .padding(.bottom, GuardianSpacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func promptCard(_ event: OperatorPromptEvent) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            OperatorPromptAttributionCaption(source: event.displaySource)
            if let reviewSurface = OperatorPromptReviewSurfaceResolver.resolve(for: event) {
                GuardianThemedButton(
                    title: reviewSurface.reviewNavigationButtonTitle,
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: {
                        operatorPromptReviewFocus.requestReviewFocus(for: event) {
                            appDrawer.dismiss()
                        }
                    }
                )
                .help(reviewSurface.reviewNavigationAccessibilityHint)
                .accessibilityHint(reviewSurface.reviewNavigationAccessibilityHint)
                .guardianPointerOnHover()
            }
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                Image(systemName: event.severity.feedbackChromeSymbol)
                    .foregroundStyle(severityColor(event.severity))
                    .font(GuardianTypography.font(.denseCaption12Medium))
                Text(event.title)
                    .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.body.isEmpty {
                Text(event.body)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.contextFacts.isEmpty {
                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    ForEach(Array(event.contextFacts.enumerated()), id: \.offset) { _, fact in
                        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xxs) {
                            Text(fact.label + ":")
                                .font(GuardianTypography.font(.denseCaption12Medium))
                                .foregroundStyle(theme.textTertiary)
                            Text(fact.value)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .padding(.top, GuardianSpacing.xxs)
            }

            if event.allowsRememberChoice {
                Toggle(
                    "Remember this choice",
                    isOn: Binding(
                        get: { rememberByPromptID[event.id, default: false] },
                        set: { rememberByPromptID[event.id] = $0 }
                    )
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .toggleStyle(.checkbox)
                .padding(.top, GuardianSpacing.xxs)
            }

            optionButtons(for: event)
        }
        .padding(GuardianSpacing.cardBodyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.displaySource.resolvedOperatorPromptCardFillColor(severityForAssistantHexFallback: event.severity))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }

    private func optionButtons(for event: OperatorPromptEvent) -> some View {
        let options = event.effectiveOptions
        return FlowOptionButtonsRow(
            options: options,
            submit: { option in
                let answer = OperatorPromptAnswer(
                    promptID: event.id,
                    selectedOptionID: option.id,
                    verb: option.verb,
                    remember: rememberByPromptID[event.id, default: false],
                    resolution: .operatorChose
                )
                if center.submitAnswer(answer) {
                    rememberByPromptID[event.id] = nil
                }
            }
        )
        .padding(.top, GuardianSpacing.xs)
    }

    private func severityColor(_ severity: GuardianFeedbackSeverity) -> Color {
        switch severity {
        case .success: return GuardianSemanticColors.successStroke
        case .info: return GuardianSemanticColors.infoForeground
        case .warning: return GuardianSemanticColors.warningStroke
        case .error: return GuardianSemanticColors.dangerStroke
        }
    }
}

// MARK: - Wrapping option strip

/// Horizontal flow of prompt options with semantic button colours.
private struct FlowOptionButtonsRow: View {
    let options: [OperatorPromptOption]
    let submit: (OperatorPromptOption) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GuardianSpacing.xs) {
                ForEach(options) { option in
                    optionButton(option)
                }
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                ForEach(options) { option in
                    optionButton(option)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ option: OperatorPromptOption) -> some View {
        switch option.role {
        case .confirm:
            GuardianPrimaryProminentButton(title: option.humanLabel) {
                submit(option)
            }
        case .cancel:
            GuardianThemedButton(
                title: option.humanLabel,
                accent: .danger,
                surface: .outline,
                action: { submit(option) }
            )
        case .neutral:
            GuardianThemedButton(
                title: option.humanLabel,
                accent: .neutral,
                surface: .outline,
                action: { submit(option) }
            )
        }
    }
}
