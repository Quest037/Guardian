import GuardianCore
import SwiftUI

@main
struct GuardianMissionApp: App {
    private static let _registerProduct: Void = {
        GuardianAppSessionBootstrap.registerActiveProduct(.mission)
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = GuardianAppSession(product: .mission)

    init() {
        _ = Self._registerProduct
        GuardianAppSessionBootstrap.bootstrapColdLaunch(for: .mission)
    }

    var body: some Scene {
        GuardianBuiltAppScene(session: session)
    }
}
