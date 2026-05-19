import SwiftUI

/// Window scene shared by all Guardian executables; ``GuardianAppSession`` is owned by each `@main` app.
public struct GuardianBuiltAppScene: Scene {
    @ObservedObject public var session: GuardianAppSession

    public init(session: GuardianAppSession) {
        self.session = session
    }

    public var body: some Scene {
        WindowGroup(session.product.displayName) {
            Group {
                if session.showingSplash {
                    TacticalSplashView(product: session.product)
                } else {
                    RootView(
                        selection: $session.selection,
                        fleetLinkService: session.fleetLinkService,
                        sitlService: session.sitlService,
                        gazeboService: session.gazeboService,
                        generalSettingsStore: session.generalSettingsStore
                    )
                    .withAppDrawer()
                    .withGuardianConfirmOverlayHost()
                    .withOperatorPromptPersistentToasts()
                    .withToasts()
                    .environmentObject(session.appDrawer)
                    .environmentObject(OperatorPromptCenter.shared)
                    .environmentObject(session.operatorPromptReviewFocusController)
                    .environmentObject(session.osmRoutingService)
                    .environment(\.guardianAppProduct, session.product)
                    .onAppear {
                        UserNotificationService.shared.configure()
                        session.clampSelectionToProduct()
                    }
                }
            }
            .environmentObject(session.toastCenter)
            .environmentObject(GuardianApplicationLifecycle.shared)
            .onReceive(NotificationCenter.default.publisher(for: GuardianReserveSwapPostCommitOperatorToastNotification.name)) { note in
                guard let message = note.userInfo?[GuardianReserveSwapPostCommitOperatorToastNotification.messageKey] as? String else { return }
                let raw = note.userInfo?[GuardianReserveSwapPostCommitOperatorToastNotification.severityRawKey] as? String
                let style = GuardianFeedbackSeverity(rawValue: raw ?? "") ?? .error
                session.toastCenter.show(message, style: style, duration: 4.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: GuardianMissionRunSimCleanupOperatorToastNotification.name)) { note in
                guard let message = note.userInfo?[GuardianMissionRunSimCleanupOperatorToastNotification.messageKey] as? String else { return }
                let raw = note.userInfo?[GuardianMissionRunSimCleanupOperatorToastNotification.severityRawKey] as? String
                let style = GuardianFeedbackSeverity(rawValue: raw ?? "") ?? .warning
                session.toastCenter.show(message, style: style, duration: 4.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: GuardianMissionRunSlotEvidenceAutoTriageToastNotification.name)) { note in
                guard let message = note.userInfo?[GuardianMissionRunSlotEvidenceAutoTriageToastNotification.messageKey] as? String else { return }
                let raw = note.userInfo?[GuardianMissionRunSlotEvidenceAutoTriageToastNotification.severityRawKey] as? String
                let style = GuardianFeedbackSeverity(rawValue: raw ?? "") ?? .success
                session.toastCenter.show(message, style: style, duration: 4.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: GuardianBrainCatalogueChangeNotification.name)) { note in
                guard session.product != .training else { return }
                guard let displayName = note.userInfo?[GuardianBrainCatalogueChangeNotification.displayNameKey] as? String,
                      let versionLabel = note.userInfo?[GuardianBrainCatalogueChangeNotification.brainVersionLabelKey] as? String
                        ?? note.userInfo?[GuardianBrainCatalogueChangeNotification.brainVersionKey] as? String
                else { return }
                session.toastCenter.show(
                    "New brain pack in catalogue: \(displayName) (\(versionLabel)). Open Settings → Brains to review or pin.",
                    style: .info,
                    duration: 5.0
                )
            }
            .environmentObject(session.guardianConfirmOverlayHost)
            .onChange(of: session.showingSplash) { stillShowingSplash in
                guard !stillShowingSplash else { return }
                Task { @MainActor in
                    UserNotificationService.shared.configure()
                    session.clampSelectionToProduct()
                }
            }
            .environmentObject(session.pluginPreferences)
            .environmentObject(GuardianPluginRegistry.shared)
            .onAppear {
                session.wireFleetAndCatalogues()
            }
            .task {
                guard session.showingSplash else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(GuardianMotion.shellCrossfade) {
                    session.showingSplash = false
                }
            }
            .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.automatic)
        .defaultSize(width: 1320, height: 860)
    }

    private var preferredColorScheme: ColorScheme? {
        switch session.generalSettingsStore.appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private struct GuardianAppProductEnvironmentKey: EnvironmentKey {
    static let defaultValue: GuardianAppProduct = .fullHQ
}

extension EnvironmentValues {
    var guardianAppProduct: GuardianAppProduct {
        get { self[GuardianAppProductEnvironmentKey.self] }
        set { self[GuardianAppProductEnvironmentKey.self] = newValue }
    }
}
