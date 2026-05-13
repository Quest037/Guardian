import SwiftUI

/// Live Drive bottom operator prompts when routing selects ``OperatorPromptDeliveryTarget/liveDrivePromptPanel``.
///
/// Uses the same docked strip chrome as ``MissionRunOperatorRecipePromptBanner`` (flush to the Live Drive
/// content column’s leading/trailing/bottom).
struct LiveDriveOperatorRecipePromptBanner: View {

    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter

    private var prompts: [OperatorPromptEvent] {
        operatorPromptCenter.activeLiveDrivePrompts
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
    }
}
