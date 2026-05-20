import GuardianCore
import SwiftUI

@main
struct GuardianTrainingApp: App {
    private static let _registerProduct: Void = {
        GuardianAppSessionBootstrap.registerActiveProduct(.training)
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = GuardianAppSession(product: .training)

    init() {
        _ = Self._registerProduct
        GuardianAppSessionBootstrap.bootstrapColdLaunch(for: .training)
    }

    var body: some Scene {
        GuardianBuiltAppScene(session: session)
    }
}
