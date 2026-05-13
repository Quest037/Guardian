import SwiftUI

// MARK: - Style

/// Solid bottom-banner semantics for ``GuardianBottomPromptCenter`` (Mission Control run, Live Drive, etc.) — distinct from ``ToastCenter`` toasts. Uses ``GuardianBottomPromptStyle`` (``GuardianFeedbackSeverity``).

// MARK: - Payload

struct GuardianBottomPrompt: Identifiable, Equatable {
    enum Buttons: Equatable {
        case singleDismiss
        case pair(confirm: String, dismiss: String)
        /// Three explicit actions (e.g. MC-R reserve swap-in arm probe failure: cancel pick vs pick another pool row vs Vehicle Inspector).
        case trio(cancelTitle: String, switchTitle: String, inspectTitle: String)
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

/// Host for a single bottom **prompt** (dismiss, confirm/dismiss, or three explicit actions). Independent from ``ToastCenter``.
@MainActor
final class GuardianBottomPromptCenter: ObservableObject {
    @Published private(set) var activePrompt: GuardianBottomPrompt?
    private var onDismissCallback: (() -> Void)?
    private var onConfirmCallback: (() -> Void)?
    private var onTrioCancel: (() -> Void)?
    private var onTrioSwitchPool: (() -> Void)?
    private var onTrioInspect: (() -> Void)?

    init() {}

    func present(_ text: String, style: GuardianBottomPromptStyle = .info, onDismiss: (() -> Void)? = nil) {
        clearTrioCallbacks()
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
        clearTrioCallbacks()
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

    /// Three actions (e.g. cancel a flow, branch to a secondary path, open tooling). Replaces any active prompt.
    func presentTripleChoice(
        _ text: String,
        style: GuardianBottomPromptStyle = .warning,
        cancelTitle: String,
        switchTitle: String,
        inspectTitle: String,
        onCancel: @escaping () -> Void,
        onSwitchPoolRow: @escaping () -> Void,
        onOpenVehicleInspector: @escaping () -> Void
    ) {
        onDismissCallback = nil
        onConfirmCallback = nil
        onTrioCancel = onCancel
        onTrioSwitchPool = onSwitchPoolRow
        onTrioInspect = onOpenVehicleInspector
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = GuardianBottomPrompt(
                text: text,
                style: style,
                buttons: .trio(cancelTitle: cancelTitle, switchTitle: switchTitle, inspectTitle: inspectTitle)
            )
        }
    }

    func dismiss() {
        clearTrioCallbacks()
        let dismissCb = onDismissCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = nil
        }
        dismissCb?()
    }

    func confirmPrimary() {
        clearTrioCallbacks()
        let confirmCb = onConfirmCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = nil
        }
        confirmCb?()
    }

    func trioCancelTapped() {
        completeTrio(onTrioCancel)
    }

    func trioSwitchTapped() {
        completeTrio(onTrioSwitchPool)
    }

    func trioInspectTapped() {
        completeTrio(onTrioInspect)
    }

    private func clearTrioCallbacks() {
        onTrioCancel = nil
        onTrioSwitchPool = nil
        onTrioInspect = nil
    }

    private func completeTrio(_ block: (() -> Void)?) {
        let action = block
        clearTrioCallbacks()
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(GuardianMotion.feedbackCrossfade) {
            activePrompt = nil
        }
        action?()
    }
}

// MARK: - Banner layout

/// Visual placement for ``GuardianBottomPromptBanner`` inside a bottom-aligned host ``ZStack``.
enum GuardianBottomPromptBannerLayout: Equatable {
    /// Inset rounded card with horizontal margins (Live Drive and general use).
    case floatingCard
    /// Mission Control run: flush to the host’s leading, trailing, and bottom edges (the host is already the main column — left meets the sidebar seam). Pass a **minimum** height (e.g. MC‑R live roster card height + a few points); the panel grows with content but does not fill the window.
    case missionControlDocked(minHeight: CGFloat)
}

// MARK: - Banner

/// Full width of the host, pinned to the **bottom** edge (place inside a ``ZStack(alignment: .bottom)``).
struct GuardianBottomPromptBanner: View {
    @ObservedObject private var center: GuardianBottomPromptCenter
    private let layout: GuardianBottomPromptBannerLayout

    init(center: GuardianBottomPromptCenter, layout: GuardianBottomPromptBannerLayout = .floatingCard) {
        self.center = center
        self.layout = layout
    }

    var body: some View {
        switch layout {
        case .floatingCard:
            floatingCardHost
        case .missionControlDocked(let minHeight):
            missionControlDockedHost(minHeight: minHeight)
        }
    }

    private var floatingCardHost: some View {
        Group {
            if let prompt = center.activePrompt {
                promptChrome(prompt: prompt, docked: false)
                    .padding(.horizontal, GuardianSpacing.sm)
                    .padding(.bottom, GuardianSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(center.activePrompt != nil)
    }

    private func missionControlDockedHost(minHeight: CGFloat) -> some View {
        let floor = max(1, minHeight)
        return Group {
            if center.activePrompt != nil {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    if let prompt = center.activePrompt {
                        promptChrome(prompt: prompt, docked: true)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: floor, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(center.activePrompt != nil)
    }

    @ViewBuilder
    private func promptChrome(prompt: GuardianBottomPrompt, docked: Bool) -> some View {
        promptRows(prompt: prompt, docked: docked)
            .padding(.horizontal, GuardianSpacing.cardBodyInset)
            .padding(.vertical, docked ? GuardianSpacing.md : GuardianSpacing.denseGutter)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(prompt.style.bottomPromptBannerBackground)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.white.opacity(0.2)),
                alignment: .top
            )
            .modifier(BottomPromptBannerShapeModifier(docked: docked))
    }

    @ViewBuilder
    private func promptRows(prompt: GuardianBottomPrompt, docked: Bool) -> some View {
        switch prompt.buttons {
        case .trio(let cancelTitle, let switchTitle, let inspectTitle):
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                    Image(systemName: prompt.style.icon)
                        .font(GuardianTypography.font(.bottomPromptIcon))
                        .foregroundStyle(.white)
                    Text(prompt.text)
                        .font(GuardianTypography.font(.bottomPromptMessage))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: cancelTitle,
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { center.trioCancelTapped() }
                    )
                    .guardianPointerOnHover()
                    GuardianThemedButton(
                        title: switchTitle,
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { center.trioSwitchTapped() }
                    )
                    .guardianPointerOnHover()
                    GuardianPrimaryProminentButton(title: inspectTitle) {
                        center.trioInspectTapped()
                    }
                    .guardianPointerOnHover()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .singleDismiss:
            if docked {
                dockedSingleOrPairBody(icon: prompt.style.icon, text: prompt.text, buttons: .singleDismiss)
            } else {
                floatingSingleOrPairBody(icon: prompt.style.icon, text: prompt.text, buttons: .singleDismiss)
            }
        case .pair(let confirm, let dismiss):
            if docked {
                dockedSingleOrPairBody(icon: prompt.style.icon, text: prompt.text, buttons: .pair(confirm: confirm, dismiss: dismiss))
            } else {
                floatingSingleOrPairBody(icon: prompt.style.icon, text: prompt.text, buttons: .pair(confirm: confirm, dismiss: dismiss))
            }
        }
    }

    private enum SingleOrPairButtons {
        case singleDismiss
        case pair(confirm: String, dismiss: String)
    }

    @ViewBuilder
    private func dockedSingleOrPairBody(icon: String, text: String, buttons: SingleOrPairButtons) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                Image(systemName: icon)
                    .font(GuardianTypography.font(.bottomPromptIcon))
                    .foregroundStyle(.white)
                Text(text)
                    .font(GuardianTypography.font(.bottomPromptMessage))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer(minLength: 0)
                switch buttons {
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
        }
    }

    @ViewBuilder
    private func floatingSingleOrPairBody(icon: String, text: String, buttons: SingleOrPairButtons) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
            Image(systemName: icon)
                .font(GuardianTypography.font(.bottomPromptIcon))
                .foregroundStyle(.white)
            Text(text)
                .font(GuardianTypography.font(.bottomPromptMessage))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch buttons {
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
    }
}

private struct BottomPromptBannerShapeModifier: ViewModifier {
    let docked: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if docked {
            content
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .guardianDropShadow(GuardianElevation.feedbackChrome)
        }
    }
}
