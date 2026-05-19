import SwiftUI

/// Shared application services for every Guardian executable (`GuardianHQ`, `GuardianMission`, `GuardianTraining`).
@MainActor
public final class GuardianAppSession: ObservableObject {
    let product: GuardianAppProduct

    @Published var selection: AppSection
    @Published var showingSplash = true

    let toastCenter = ToastCenter()
    let guardianConfirmOverlayHost = GuardianConfirmOverlayHost()
    let appDrawer = AppDrawer()
    let fleetLinkService = FleetLinkService()
    let sitlService = SitlService()
    let gazeboService = GazeboService()
    let generalSettingsStore = GeneralSettingsStore()
    let osmRoutingService = OSMRoutingService()
    let pluginPreferences = PluginPreferencesStore()
    let operatorPromptReviewFocusController = OperatorPromptReviewFocusController()

    public init(product: GuardianAppProduct) {
        GuardianAppSessionBootstrap.registerActiveProduct(product)
        self.product = product
        self.selection = product.defaultAppSection
    }

    func wireFleetAndCatalogues() {
        sitlService.attachFleetLink(fleetLinkService)
        if product.includesGazeboSimulation {
            gazeboService.attachFleetLink(fleetLinkService)
            sitlService.attachGazebo(gazeboService)
        }
        GuardianPluginRegistry.shared.bindPreferences(pluginPreferences)
        GuardianPluginBootstrap.ensureRegistered()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetRecipesCatalogueBootstrap.ensureRegistered()
        fleetLinkService.beginFleetNav2WarmStartAtApplicationLaunch()
    }

    func clampSelectionToProduct() {
        guard !product.includesSidebarSection(selection) else { return }
        selection = product.defaultAppSection
    }
}
