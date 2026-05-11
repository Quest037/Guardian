import SwiftUI

// MARK: - Style

/// Solid bottom-banner semantics for ``GuardianBottomPromptCenter`` (Mission Control run, Live Drive, etc.) — distinct from ``ToastCenter`` toasts. Uses ``GuardianBottomPromptStyle`` (``GuardianFeedbackSeverity``).

// MARK: - Payload

struct GuardianBottomPrompt: Identifiable, Equatable {
    enum Buttons: Equatable {
        case singleDismiss
        case pair(confirm: String, dismiss: String)
    }

    let id: UUID
    let text: String
    let style: GuardianBottomPromptStyle
    let buttons: Buttons

    init(text: String, style: GuardianBottomPromptStyle, buttons: Buttons = .singleDismiss) {
        self.id = UUID()
        self.text = text
        self.style = style
        self.buttons = buttons
    }
}

// MARK: - Center

/// Host for a single bottom **prompt** (dismiss or confirm/dismiss). Independent from ``ToastCenter``.
@MainActor
final class GuardianBottomPromptCenter: ObservableObject {
    @Published private(set) var activePrompt: GuardianBottomPrompt?
    private var onDismissCallback: (() -> Void)?
    private var onConfirmCallback: (() -> Void)?

    init() {}

    func present(_ text: String, style: GuardianBottomPromptStyle = .info, onDismiss: (() -> Void)? = nil) {
        onDismissCallback = onDismiss
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = GuardianBottomPrompt(text: text, style: style, buttons: .singleDismiss)
        }
    }

    /// Two actions (e.g. **Keep running** vs **Dismiss**). `onDismiss` runs only for the dismiss control.
    func presentChoice(
        _ text: String,
        style: GuardianBottomPromptStyle = .warning,
        confirmTitle: String,
        dismissTitle: String,
        onConfirm: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        onDismissCallback = onDismiss
        onConfirmCallback = onConfirm
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = GuardianBottomPrompt(
                text: text,
                style: style,
                buttons: .pair(confirm: confirmTitle, dismiss: dismissTitle)
            )
        }
    }

    func dismiss() {
        let dismissCb = onDismissCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = nil
        }
        dismissCb?()
    }

    func confirmPrimary() {
        let confirmCb = onConfirmCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = nil
        }
        confirmCb?()
    }
}

// MARK: - Banner

/// Full width of the host, pinned to the **bottom** edge (place inside a ``ZStack(alignment: .bottom)``).
struct GuardianBottomPromptBanner: View {
    @ObservedObject private var center: GuardianBottomPromptCenter

    init(center: GuardianBottomPromptCenter) {
        self.center = center
    }

    var body: some View {
        Group {
            if let prompt = center.activePrompt {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    Image(systemName: prompt.style.icon)
                        .font(GuardianTypography.font(.bottomPromptIcon))
                        .foregroundStyle(.white)
                    Text(prompt.text)
                        .font(GuardianTypography.font(.bottomPromptMessage))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    switch prompt.buttons {
                    case .singleDismiss:
                        Button("Dismiss") {
                            center.dismiss()
                        }
                        .buttonStyle(.bordered).guardianPointerOnHover()
                        .controlSize(.small)
                        .tint(.white)
                    case let .pair(confirm, dismiss):
                        HStack(spacing: GuardianSpacing.xs) {
                            Button(dismiss) {
                                center.dismiss()
                            }
                            .buttonStyle(.bordered).guardianPointerOnHover()
                            .controlSize(.small)
                            .tint(.white)
                            Button(confirm) {
                                center.confirmPrimary()
                            }
                            .buttonStyle(.borderedProminent).guardianPointerOnHover()
                            .tint(.blue)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, GuardianSpacing.cardBodyInset)
                .padding(.vertical, GuardianSpacing.denseGutter)
                .background(prompt.style.bottomPromptBannerBackground)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.white.opacity(0.2)),
                    alignment: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .guardianDropShadow(GuardianElevation.feedbackChrome)
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.bottom, GuardianSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        // When idle this host is layout-only; without this, the framed `Group` can still
        // occupy the full ZStack proposal and **steal all clicks** from the map / WKWebView below (MC-R, Live Drive).
        .allowsHitTesting(center.activePrompt != nil)
    }
}
