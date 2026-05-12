import SwiftUI

/// Live Drive bottom operator prompts when routing selects ``OperatorPromptDeliveryTarget/liveDrivePromptPanel``.
struct LiveDriveOperatorRecipePromptBanner: View {

    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter

    private var prompts: [OperatorPromptEvent] {
        operatorPromptCenter.activeLiveDrivePrompts
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
                                _ = operatorPromptCenter.submitAnswer(answer)
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
