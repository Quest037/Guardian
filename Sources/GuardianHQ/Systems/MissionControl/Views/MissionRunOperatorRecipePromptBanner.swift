import SwiftUI

/// MC-R bottom operator prompts for recipe escalations raised by MRE (headless recipe runs).
/// Uses ``MissionRunRecipeOperatorPromptBridge`` + ``OperatorPromptResumptionChannel``; styling aligns with ``GuardianBottomPromptBanner``.
struct MissionRunOperatorRecipePromptBanner: View {
    let missionRunID: UUID

    @ObservedObject private var bridge = MissionRunRecipeOperatorPromptBridge.shared

    private var prompts: [OperatorPromptEvent] {
        bridge.activePrompts(forMissionRunID: missionRunID)
    }

    var body: some View {
        Group {
            if !prompts.isEmpty {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(prompts, id: \.id) { event in
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
                                bridge.submitOperatorAnswer(answer)
                            }
                        )
                    }
                }
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.bottom, GuardianSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(GuardianMotion.feedbackCrossfade, value: prompts.map(\.id))
        .allowsHitTesting(!prompts.isEmpty)
    }
}

// MARK: - Card

private struct MissionRunOperatorRecipePromptCard: View {
    let event: OperatorPromptEvent
    let onSelectOption: (OperatorPromptOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                Image(systemName: event.severity.icon)
                    .font(GuardianTypography.font(.bottomPromptIcon))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    Text(event.title)
                        .font(GuardianTypography.font(.bottomPromptMessage))
                        .foregroundStyle(.white)
                    if !event.body.isEmpty {
                        Text(event.body)
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !event.contextFacts.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(event.contextFacts.enumerated()), id: \.offset) { _, fact in
                                HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xsTight) {
                                    Text(fact.label + ":")
                                        .font(GuardianTypography.font(.denseCaption10Semibold))
                                        .foregroundStyle(.white.opacity(0.75))
                                    Text(fact.value)
                                        .font(GuardianTypography.font(.denseCaption10Regular))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FlowOperatorPromptOptionButtons(options: event.effectiveOptions, onSelect: onSelectOption)
        }
        .modifier(MissionRunOperatorRecipePromptExpiryModifier(event: event))
        .padding(.horizontal, GuardianSpacing.cardBodyInset)
        .padding(.vertical, GuardianSpacing.denseGutter)
        .background(event.severity.bottomPromptBannerBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.2)),
            alignment: .top
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .guardianDropShadow(GuardianElevation.feedbackChrome)
    }
}

// MARK: - Option buttons

private struct FlowOperatorPromptOptionButtons: View {
    let options: [OperatorPromptOption]
    let onSelect: (OperatorPromptOption) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GuardianSpacing.xs) {
                ForEach(options, id: \.id) { option in
                    optionButton(option)
                }
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                ForEach(options, id: \.id) { option in
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
            .tint(.white)
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
            .tint(.white)
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
                MissionRunRecipeOperatorPromptBridge.shared.resolveExpiry(for: event)
            }
        }
    }
}
