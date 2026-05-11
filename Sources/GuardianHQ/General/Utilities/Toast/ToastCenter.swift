import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published var current: ToastMessage?
    private var dismissTask: DispatchWorkItem?

    func show(_ text: String, style: ToastStyle = .info, duration: TimeInterval = 2.2) {
        dismissTask?.cancel()
        withAnimation(GuardianMotion.feedbackCrossfade) {
            current = ToastMessage(text: text, style: style)
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(GuardianMotion.feedbackCrossfade) {
                self.current = nil
            }
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

struct ToastHost: ViewModifier {
    @EnvironmentObject private var toastCenter: ToastCenter

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content

            if let toast = toastCenter.current {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    Image(systemName: toast.style.icon)
                    Text(toast.text)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(GuardianTypography.font(.toastEphemeral))
                .foregroundStyle(.white)
                .padding(.horizontal, GuardianSpacing.cardBodyInset)
                .padding(.vertical, GuardianSpacing.denseGutter)
                .background(toastEphemeralBackground(for: toast.style))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .guardianDropShadow(GuardianElevation.feedbackChrome)
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.leading, GuardianSpacing.cardBodyInset)
                .padding(.top, GuardianSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// App-wide ephemeral toasts: more readable than ``GuardianFeedbackSeverity/legacyTranslucentChipBackground``, less heavy than MC-R banners.
    private func toastEphemeralBackground(for style: ToastStyle) -> Color {
        style.toastEphemeralSolidBackground
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastHost())
    }
}
