import SwiftUI

// MARK: - Shell anchor (window-level toast host)

/// Metrics published from ``RootView`` so ``ToastHost`` can align with the window **top bar** (Simulate + appearance)
/// while hosting at the outermost window shell layer (above drawer, in-window modals, and blocking confirms — see
/// ``GuardianLayoutPatterns``).
struct GuardianToastShellAnchor: Equatable {
    /// Top chrome height (``RootView`` top bar).
    var topBarHeight: CGFloat
    /// Trailing inset from the window edge; matches ``RootView`` top-bar trailing padding.
    var topBarTrailingInset: CGFloat

    static let `default` = GuardianToastShellAnchor(topBarHeight: 52, topBarTrailingInset: GuardianSpacing.md)
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
    /// Main-queue auto-dismiss. Prefer this over `Task.sleep` so dismissal stays tied to the UI run loop
    /// and `cancel()` is deterministic while coalescing duplicate ``show`` calls.
    private var dismissWorkItem: DispatchWorkItem?
    /// Bumped on every **distinct** ``show`` (new text/style) and on ``dismiss()`` so a stale auto-dismiss
    /// cannot clear a newer message after the work item is superseded.
    private var dismissGeneration: UInt64 = 0

    func show(_ text: String, style: ToastStyle = .info, duration: TimeInterval = 2.2) {
        cancelScheduledDismiss()

        let boundedDuration: TimeInterval = {
            guard duration.isFinite, duration > 0 else { return 2.2 }
            return min(max(0.3, duration), 600)
        }()

        if let existing = current, existing.text == text, existing.style == style {
            // Identical toast re-fired while still visible: slide the deadline only. Bumping
            // `dismissGeneration` here would match the old "never auto-dismiss" failure mode when
            // callers spam the same line (telemetry hooks, tight UI feedback loops).
            scheduleDismiss(after: boundedDuration, generation: dismissGeneration)
            return
        }

        dismissGeneration += 1
        let generation = dismissGeneration
        withAnimation(GuardianMotion.feedbackCrossfade) {
            current = ToastMessage(text: text, style: style)
        }
        scheduleDismiss(after: boundedDuration, generation: generation)
    }

    /// Hides the current toast immediately (e.g. operator tap). Cancels any pending
    /// auto-dismiss so a stale timer cannot fire after manual dismiss.
    func dismiss() {
        cancelScheduledDismiss()
        dismissGeneration += 1
        withAnimation(GuardianMotion.feedbackCrossfade) {
            current = nil
        }
    }

    private func cancelScheduledDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func scheduleDismiss(after delay: TimeInterval, generation: UInt64) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // `asyncAfter` onto the main queue is enough: do **not** nest `Task { @MainActor }` here — that
            // extra hop can reorder behind other UI work and matches “toast never clears until something
            // else pokes the main actor” reports.
            MainActor.assumeIsolated {
                guard generation == self.dismissGeneration else { return }
                // Auto-dismiss: clear without animation. Animated `nil` transitions have been observed to leave
                // the chip visually stuck while `current` is already `nil` (insert uses animation; dismiss does not).
                self.current = nil
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Hosts a single ephemeral toast. Attach with ``View/withToasts()`` **after**
/// ``View/withGuardianConfirmOverlayHost()`` on the window root (see ``GuardianHQApp`` / ``GuardianLayoutPatterns``).
struct ToastHost: ViewModifier {
    @EnvironmentObject private var toastCenter: ToastCenter
    @State private var shellAnchor: GuardianToastShellAnchor = .default

    /// Above app drawer (`zIndex` 101), in-window overlays, and blocking confirms (`zIndex` 10_000).
    private static let overlayZIndex: Double = 15_000

    /// Nudges the chip vertically into the top bar without ``GeometryReader`` (one-line toasts ≈40pt tall).
    private var toastTopInsetInTopBar: CGFloat {
        let assumedChipHeight: CGFloat = 40
        let raw = (shellAnchor.topBarHeight - assumedChipHeight) * 0.5
        return max(GuardianSpacing.xxs, min(raw, GuardianSpacing.sm))
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(GuardianToastShellAnchorPreferenceKey.self) { shellAnchor = $0 }
            .overlay(alignment: .topTrailing) {
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
                    .padding(.top, toastTopInsetInTopBar)
                    .padding(.trailing, shellAnchor.topBarTrailingInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
