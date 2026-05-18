import SwiftUI

// MARK: - Tokens + panel chrome

private enum GuardianConfirmOverlayTokens {
    static let scrimOpacity: Double = 0.28
    static let transitionScale: CGFloat = 0.98
}

/// Width and horizontal padding for ``GuardianConfirm`` / ``GuardianConfirmDanger`` when presented with ``View/guardianConfirmOverlay(isPresented:dialog:)`` or ``View/guardianConfirmOverlay(item:onDismiss:dialog:)``.
struct GuardianConfirmPanelFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, GuardianSpacing.xl)
            .frame(minWidth: 420, idealWidth: 440, maxWidth: 520)
    }
}

// MARK: - App-wide host (covers sidebar + top bar + drawer)

/// Single window-level confirm overlay. Screens use ``View/guardianConfirmOverlay(isPresented:dialog:)`` /
/// ``View/guardianConfirmOverlay(item:onDismiss:dialog:)``; attach ``View/withGuardianConfirmOverlayHost()`` **outside**
/// ``View/withAppDrawer()`` on the window root so the scrim blocks the drawer and all chrome (see ``GuardianLayoutPatterns``).
@MainActor
final class GuardianConfirmOverlayHost: ObservableObject {
    struct ActiveSession {
        let ownerID: UUID
        /// Sets the originating screen’s binding to a dismissed state (e.g. `false` / `nil`).
        let syncDismiss: () -> Void
        /// Cleanup when the overlay is removed without relying on button handlers (Escape, navigation, preemption).
        let onTeardown: (() -> Void)?
        let build: () -> AnyView
    }

    @Published private(set) var session: ActiveSession?
    /// Bumps whenever ``session`` changes so the root layer can animate transitions reliably.
    @Published private(set) var presentationEpoch: UInt = 0

    func present<Dialog: View>(
        ownerID: UUID,
        syncDismiss: @escaping () -> Void,
        onTeardown: (() -> Void)?,
        @ViewBuilder dialog: @escaping () -> Dialog
    ) {
        if let existing = session, existing.ownerID != ownerID {
            clearSession(existing, syncBinding: true, runTeardown: true, animated: false)
        }
        withAnimation(GuardianMotion.confirmPresent) {
            session = ActiveSession(
                ownerID: ownerID,
                syncDismiss: syncDismiss,
                onTeardown: onTeardown,
                build: { AnyView(dialog()) }
            )
            presentationEpoch &+= 1
        }
    }

    /// Binding already reflects dismissal (e.g. user tapped Cancel); only run teardown and clear the host.
    func dismissIfOwner(_ ownerID: UUID) {
        guard let s = session, s.ownerID == ownerID else { return }
        clearSession(s, syncBinding: false, runTeardown: true, animated: false)
    }

    /// Escape / chrome: sync bindings first, then teardown, then clear.
    func dismissFromChrome(ownerID: UUID) {
        guard let s = session, s.ownerID == ownerID else { return }
        clearSession(s, syncBinding: true, runTeardown: true, animated: false)
    }

    /// View removed while still presented (tab change, navigation) — force bindings to dismiss and tear down.
    func abandonOwner(_ ownerID: UUID) {
        guard let s = session, s.ownerID == ownerID else { return }
        clearSession(s, syncBinding: true, runTeardown: true, animated: false)
    }

    private func clearSession(
        _ s: ActiveSession,
        syncBinding: Bool,
        runTeardown: Bool,
        animated: Bool
    ) {
        if syncBinding {
            s.syncDismiss()
        }
        if runTeardown {
            s.onTeardown?()
        }
        let apply = {
            self.session = nil
            self.presentationEpoch &+= 1
        }
        if animated {
            withAnimation(GuardianMotion.confirmPresent, apply)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        }
        GuardianPresentationChromeTeardown.run()
    }
}

// MARK: - Visual layer (scrim + panel + shadow + escape)

private struct GuardianConfirmOverlayScrimAndPanel<Panel: View>: View {
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        ZStack {
            Color.black.opacity(GuardianConfirmOverlayTokens.scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            panel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GuardianConfirmOverlayEscapeModifier: ViewModifier {
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .focusable()
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
        } else {
            content
        }
    }
}

private struct GuardianConfirmOverlayRootLayer: View {
    @ObservedObject var host: GuardianConfirmOverlayHost
    let session: GuardianConfirmOverlayHost.ActiveSession

    var body: some View {
        GuardianConfirmOverlayScrimAndPanel {
            GuardianConfirmPanelFrame {
                session.build()
            }
        }
        .guardianDropShadow(GuardianElevation.overlayPanel)
        .transition(.opacity.combined(with: .scale(scale: GuardianConfirmOverlayTokens.transitionScale)))
        .modifier(GuardianConfirmOverlayEscapeModifier {
            host.dismissFromChrome(ownerID: session.ownerID)
        })
        .onDisappear {
            GuardianPresentationChromeTeardown.run()
        }
        .zIndex(10_000)
    }
}

private struct GuardianConfirmOverlayRootModifier: ViewModifier {
    @EnvironmentObject private var host: GuardianConfirmOverlayHost

    func body(content: Content) -> some View {
        ZStack {
            content
            if let session = host.session {
                GuardianConfirmOverlayRootLayer(host: host, session: session)
                    .transition(.opacity.combined(with: .scale(scale: GuardianConfirmOverlayTokens.transitionScale)))
            }
        }
        .animation(GuardianMotion.confirmPresent, value: host.presentationEpoch)
    }
}

extension View {
    /// Hosts window-level Guardian confirm overlays above the main shell (sidebar, top bar, and ``View/withAppDrawer()``).
    func withGuardianConfirmOverlayHost() -> some View {
        modifier(GuardianConfirmOverlayRootModifier())
    }
}

// MARK: - Registration (child views → host)

private struct GuardianConfirmOverlayBoolRegistrationModifier<Dialog: View>: ViewModifier {
    @EnvironmentObject private var host: GuardianConfirmOverlayHost
    @Binding var isPresented: Bool
    @ViewBuilder var dialog: () -> Dialog
    @State private var ownerID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { syncToHost() }
            .onChange(of: isPresented) { _ in syncToHost() }
            .onDisappear { host.abandonOwner(ownerID) }
    }

    private func syncToHost() {
        if isPresented {
            host.present(
                ownerID: ownerID,
                syncDismiss: { isPresented = false },
                onTeardown: nil,
                dialog: dialog
            )
        } else {
            host.dismissIfOwner(ownerID)
        }
    }
}

private struct GuardianConfirmOverlayItemRegistrationModifier<Item: Identifiable, Dialog: View>: ViewModifier {
    @EnvironmentObject private var host: GuardianConfirmOverlayHost
    @Binding var item: Item?
    var onDismiss: () -> Void
    @ViewBuilder var dialog: (Item) -> Dialog
    @State private var ownerID = UUID()

    private var itemIdentityKey: String {
        guard let item else { return "" }
        return String(describing: item.id)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { syncToHost() }
            .onChange(of: itemIdentityKey) { _ in syncToHost() }
            .onDisappear { host.abandonOwner(ownerID) }
    }

    private func syncToHost() {
        if let presented = item {
            host.present(
                ownerID: ownerID,
                syncDismiss: { item = nil },
                onTeardown: onDismiss,
                dialog: { dialog(presented) }
            )
        } else {
            host.dismissIfOwner(ownerID)
        }
    }
}

extension View {
    /// Presents a centered confirm over a dimmed scrim at **window** scope (see ``withGuardianConfirmOverlayHost()``).
    func guardianConfirmOverlay<Dialog: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder dialog: @escaping () -> Dialog
    ) -> some View {
        modifier(GuardianConfirmOverlayBoolRegistrationModifier(isPresented: isPresented, dialog: dialog))
    }

    /// Presents a confirm keyed by an optional ``Identifiable``, with `onDismiss` when the overlay is torn down (Escape, programmatic `nil`, navigation, etc.).
    func guardianConfirmOverlay<Item: Identifiable, Dialog: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder dialog: @escaping (Item) -> Dialog
    ) -> some View {
        modifier(GuardianConfirmOverlayItemRegistrationModifier(item: item, onDismiss: onDismiss, dialog: dialog))
    }
}
