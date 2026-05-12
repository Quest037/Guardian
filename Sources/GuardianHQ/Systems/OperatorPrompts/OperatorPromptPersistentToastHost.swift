import SwiftUI

// MARK: - Content anchor (top-leading, primary column)

/// Metrics published from ``RootView`` so ``OperatorPromptPersistentToastHost`` can align with the
/// **primary content** region: below the window top bar and to the right of the nav rail. Keeps chips off
/// the sidebar and clear of bottom Mission Control / Live Drive operator prompt strips (which are
/// screen-local at the bottom of `content`).
struct GuardianOperatorPromptPersistentAnchor: Equatable {
    /// Distance from the window’s leading edge to the **content** column (nav rail width + gutter).
    var leadingContentInset: CGFloat
    /// Distance from the window’s top edge to the **content** area below the top bar.
    var topContentInset: CGFloat

    /// Matches collapsed rail + top bar when preferences have not propagated yet.
    static let `default` = GuardianOperatorPromptPersistentAnchor(
        leadingContentInset: 72 + GuardianSpacing.md,
        topContentInset: 52 + GuardianSpacing.sm
    )
}

enum GuardianOperatorPromptPersistentAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: GuardianOperatorPromptPersistentAnchor { .default }

    static func reduce(value: inout GuardianOperatorPromptPersistentAnchor, nextValue: () -> GuardianOperatorPromptPersistentAnchor) {
        value = nextValue()
    }
}

// MARK: - OperatorPromptPersistentToastHost

/// Window-level **sticky** operator-prompt chips when routing selects
/// ``OperatorPromptDeliveryTarget/persistentToast``. Distinct from ephemeral
/// ``ToastCenter`` / ``View/withToasts()`` — these stay until the prompt resolves
/// and open the Decisions drawer on tap so the operator can answer without hunting
/// the sidebar tray icon.
///
/// ## Placement
///
/// Chips anchor to the **top-leading corner of the primary content column** (below the top bar,
/// east of the sidebar) using ``GuardianOperatorPromptPersistentAnchorPreferenceKey`` from ``RootView``.
/// That keeps them away from bottom MC-R / Live Drive operator prompt strips.
///
/// ## Modifier order
///
/// Apply **after** ``View/withGuardianConfirmOverlayHost()`` and **before**
/// ``View/withToasts()`` on the window root so ephemeral toasts remain visually
/// above this layer (see ``GuardianLayoutPatterns``).
private struct OperatorPromptPersistentToastHost: ViewModifier {

    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter
    @EnvironmentObject private var appDrawer: AppDrawer
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentAnchor: GuardianOperatorPromptPersistentAnchor = .default

    /// Above blocking confirm (`zIndex` 10_000); below ephemeral ``ToastHost`` (`zIndex` 15_000).
    private static let overlayZIndex: Double = 12_000

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(GuardianOperatorPromptPersistentAnchorPreferenceKey.self) { contentAnchor = $0 }
            .overlay(alignment: .topLeading) {
                persistentStack
                    .zIndex(Self.overlayZIndex)
            }
    }

    @ViewBuilder
    private var persistentStack: some View {
        let theme = GuardianTheme.palette(for: colorScheme)
        if !operatorPromptCenter.persistentOperatorToastPrompts.isEmpty {
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                ForEach(operatorPromptCenter.persistentOperatorToastPrompts) { event in
                    persistentToastChip(event: event, theme: theme)
                }
            }
            .padding(.leading, contentAnchor.leadingContentInset)
            .padding(.top, contentAnchor.topContentInset)
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private func persistentToastChip(event: OperatorPromptEvent, theme: GuardianThemePalette) -> some View {
        Button {
            presentDecisionsDrawer()
        } label: {
            HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                Image(systemName: event.severity.feedbackChromeSymbol)
                    .foregroundStyle(severityColor(event.severity))
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    OperatorPromptAttributionCaption(source: event.displaySource)
                    Text(event.title)
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Tap to open Decisions and respond.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GuardianSpacing.cardBodyInset)
            .padding(.vertical, GuardianSpacing.denseGutter)
            .background(event.displaySource.resolvedOperatorPromptCardFillColor(severityForAssistantHexFallback: event.severity))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .guardianDropShadow(GuardianElevation.feedbackChrome)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .guardianPointerOnHover()
        .accessibilityLabel(event.title)
        .accessibilityHint("Opens the Decisions drawer to respond.")
    }

    private func presentDecisionsDrawer() {
        appDrawer.present(title: "Decisions", preferredWidth: 420) {
            OperatorPromptInboxDrawerView()
        }
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

extension View {
    /// Hosts sticky top-leading (primary content column) operator prompt chips for
    /// ``OperatorPromptDeliveryTarget/persistentToast`` (see ``OperatorPromptCenter``).
    func withOperatorPromptPersistentToasts() -> some View {
        modifier(OperatorPromptPersistentToastHost())
    }
}
