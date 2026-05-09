import SwiftUI

// MARK: - Presentation model

/// One trailing slide-in panel + scrim. Content is type-erased so any screen can present from the shared host.
@MainActor
struct PresentedSidebar: Identifiable {
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

/// App-wide trailing sidebar overlays (scrim + slide). Inject via environment and attach ``View/withSidebarOverlay()`` on the window root (after ``RootView``).
///
/// Ephemeral app toasts use a separate ``View/withToasts()`` host on the **main content** column inside ``RootView`` so they do not cover the nav rail. Apply ``withSidebarOverlay()`` on the outer window root so drawers stack above primary UI.
@MainActor
final class SidebarOverlay: ObservableObject {
    @Published private(set) var presented: PresentedSidebar?

    /// Drives `animation(_:value:)` in the host so insert/remove animate reliably.
    @Published private(set) var presentationRevision: UInt = 0

    /// Present or replace the current sidebar. Uses `withAnimation` internally.
    func present<Content: View>(
        title: String?,
        preferredWidth: CGFloat = 380,
        scrimTapDismisses: Bool = true,
        animation: Animation = .easeInOut(duration: 0.2),
        @ViewBuilder content: @escaping () -> Content
    ) {
        let clampedWidth = min(560, max(260, preferredWidth))
        let payload = PresentedSidebar(
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
        let anim = animation ?? presented?.animation ?? .easeInOut(duration: 0.2)
        withAnimation(anim) {
            presented = nil
            presentationRevision &+= 1
        }
    }
}

// MARK: - Chrome (optional; use in custom panels when `title == nil`)

/// Standard sidebar header matching Mission roster / Live Drive pickers: elevated strip, bold title, hierarchical close.
struct SidebarOverlayChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.backgroundElevated)

            content()
        }
    }
}

// MARK: - Host

private struct SidebarOverlayHostModifier: ViewModifier {
    @EnvironmentObject private var sidebarOverlay: SidebarOverlay
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    func body(content: Content) -> some View {
        ZStack {
            content

            if sidebarOverlay.presented != nil {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard sidebarOverlay.presented?.scrimTapDismisses == true else { return }
                        sidebarOverlay.dismiss()
                    }
                    .transition(.opacity)
                    .zIndex(100)
            }

            if let item = sidebarOverlay.presented {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sidebarPanel(for: item)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }
        }
        .animation(
            sidebarOverlay.presented?.animation ?? .easeInOut(duration: 0.2),
            value: sidebarOverlay.presentationRevision
        )
    }

    @ViewBuilder
    private func sidebarPanel(for item: PresentedSidebar) -> some View {
        Group {
            if let title = item.title {
                SidebarOverlayChrome(title: title, onClose: { sidebarOverlay.dismiss() }) {
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
            sidebarOverlay.dismiss()
        }
    }
}

extension View {
    func withSidebarOverlay() -> some View {
        modifier(SidebarOverlayHostModifier())
    }
}
