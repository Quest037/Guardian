import SwiftUI

// MARK: - Presentation model

/// One trailing slide-in panel + scrim. Content is type-erased so any screen can present from the shared host.
///
/// **Naming:** In Guardian, **drawer** means this ``AppDrawer`` host (trailing overlay). **Sidebar** means the app’s main navigation rail in ``RootView`` — do not conflate the two.
@MainActor
struct PresentedAppDrawer: Identifiable {
    let id: UUID
    /// When non-`nil`, the host prepends the standard title row + close control above `content`.
    let title: String?
    let preferredWidth: CGFloat
    let scrimTapDismisses: Bool
    let animation: Animation
    /// Rebuilt whenever the overlay host body runs so bindings to parent `@State` stay live (a single captured `AnyView` would freeze at `present()` time).
    let content: () -> AnyView
}

// MARK: - App host

/// App-wide trailing **drawer** (scrim + slide-in panel). Not the main navigation **sidebar**.
///
/// Inject via environment and attach ``View/withAppDrawer()`` on the window root (after ``RootView``).
///
/// Ephemeral app toasts use ``View/withToasts()`` **after** ``withGuardianConfirmOverlayHost()`` on the window root so
/// they paint **above** the drawer and blocking confirms; ``RootView`` publishes ``GuardianToastShellAnchorPreferenceKey``
/// for top-bar alignment (top-trailing over the Simulate + appearance cluster) — see ``GuardianLayoutPatterns``.
@MainActor
final class AppDrawer: ObservableObject {
    @Published private(set) var presented: PresentedAppDrawer?

    /// Drives `animation(_:value:)` in the host so insert/remove animate reliably.
    @Published private(set) var presentationRevision: UInt = 0

    /// Present or replace the current drawer. Uses `withAnimation` internally.
    func present<Content: View>(
        title: String?,
        preferredWidth: CGFloat = 380,
        scrimTapDismisses: Bool = true,
        animation: Animation = GuardianMotion.drawerSlide,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let clampedWidth = min(560, max(260, preferredWidth))
        let payload = PresentedAppDrawer(
            id: UUID(),
            title: title,
            preferredWidth: clampedWidth,
            scrimTapDismisses: scrimTapDismisses,
            animation: animation,
            content: { AnyView(content()) }
        )
        withAnimation(animation) {
            presented = payload
            presentationRevision &+= 1
        }
    }

    func dismiss(animation: Animation? = nil) {
        let anim = animation ?? presented?.animation ?? GuardianMotion.drawerSlide
        withAnimation(anim) {
            presented = nil
            presentationRevision &+= 1
        }
    }
}

// MARK: - Chrome (optional; use in custom panels when `title == nil`)

/// Standard drawer header (title row + close): elevated strip, bold title, hierarchical close.
struct AppDrawerChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text(title)
                    .font(GuardianTypography.font(.hudTitle16Bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GuardianSpacing.xs)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(GuardianTypography.font(.heroGlyph18Medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .background(theme.backgroundElevated)

            GuardianModalHeaderSeparator()

            // One continuous elevated surface with the host panel (see Theme catalog App drawer): body matches header token;
            // child views should not paint their own full-panel `backgroundBase` unless they intentionally inset a sheet.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(theme.backgroundElevated)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Host

private struct AppDrawerHostModifier: ViewModifier {
    @EnvironmentObject private var appDrawer: AppDrawer
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    func body(content: Content) -> some View {
        ZStack {
            content

            if appDrawer.presented != nil {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard appDrawer.presented?.scrimTapDismisses == true else { return }
                        appDrawer.dismiss()
                    }
                    .transition(.opacity)
                    .zIndex(100)
            }

            if let item = appDrawer.presented {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    drawerPanel(for: item)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }
        }
        .animation(
            appDrawer.presented?.animation ?? GuardianMotion.drawerSlide,
            value: appDrawer.presentationRevision
        )
    }

    @ViewBuilder
    private func drawerPanel(for item: PresentedAppDrawer) -> some View {
        Group {
            if let title = item.title {
                AppDrawerChrome(title: title, onClose: { appDrawer.dismiss() }) {
                    item.content()
                }
            } else {
                item.content()
            }
        }
        .frame(width: item.preferredWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.backgroundElevated)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
        .onExitCommand {
            appDrawer.dismiss()
        }
    }
}

extension View {
    func withAppDrawer() -> some View {
        modifier(AppDrawerHostModifier())
    }
}
