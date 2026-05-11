import SwiftUI

// MARK: - Shell anchor (window-level toast host)

/// Metrics published from ``RootView`` so ``ToastHost`` can pin to the **content** column while hosting at the outermost
/// window shell layer (above drawer, in-window modals, and blocking confirms — see ``GuardianLayoutPatterns``).
struct GuardianToastShellAnchor: Equatable {
    var sidebarWidth: CGFloat
    var topBarHeight: CGFloat

    static let `default` = GuardianToastShellAnchor(sidebarWidth: 260, topBarHeight: 52)
}

enum GuardianToastShellAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: GuardianToastShellAnchor { .default }

    static func reduce(value: inout GuardianToastShellAnchor, nextValue: () -> GuardianToastShellAnchor) {
        value = nextValue()
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?
    /// Bumped on every ``show`` so a stale auto-dismiss (from a prior toast) cannot
    /// clear a newer message after `Task.cancel` races with `Task.sleep` completion.
    private var dismissGeneration: UInt64 = 0

    func show(_ text: String, style: ToastStyle = .info, duration: TimeInterval = 2.2) {
        dismissTask?.cancel()
        dismissTask = nil
        dismissGeneration += 1
        let generation = dismissGeneration
        let nanoseconds = UInt64(max(0.3, duration) * 1_000_000_000)
        withAnimation(GuardianMotion.feedbackCrossfade) {
            current = ToastMessage(text: text, style: style)
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard generation == self.dismissGeneration else { return }
            withAnimation(GuardianMotion.feedbackCrossfade) {
                self.current = nil
            }
        }
    }

    /// Hides the current toast immediately (e.g. operator tap). Cancels any pending
    /// auto-dismiss so a stale timer cannot fire after manual dismiss.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        dismissGeneration += 1
        withAnimation(GuardianMotion.feedbackCrossfade) {
            current = nil
        }
    }
}

/// Hosts a single ephemeral toast. Attach with ``View/withToasts()`` **after**
/// ``View/withGuardianConfirmOverlayHost()`` on the window root (see ``GuardianHQApp`` / ``GuardianLayoutPatterns``).
struct ToastHost: ViewModifier {
    @EnvironmentObject private var toastCenter: ToastCenter
    @State private var shellAnchor: GuardianToastShellAnchor = .default

    /// Above app drawer (`zIndex` 101), in-window overlays, and blocking confirms (`zIndex` 10_000).
    private static let overlayZIndex: Double = 15_000

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .onPreferenceChange(GuardianToastShellAnchorPreferenceKey.self) { shellAnchor = $0 }

            if let toast = toastCenter.current {
                Button {
                    toastCenter.dismiss()
                } label: {
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
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .guardianDropShadow(GuardianElevation.feedbackChrome)
                    .frame(maxWidth: 380, alignment: .leading)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .guardianPointerOnHover()
                .accessibilityLabel(toast.text)
                .accessibilityHint("Tap to dismiss")
                .padding(.leading, shellAnchor.sidebarWidth + GuardianSpacing.cardBodyInset)
                .padding(.top, shellAnchor.topBarHeight + GuardianSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(Self.overlayZIndex)
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
