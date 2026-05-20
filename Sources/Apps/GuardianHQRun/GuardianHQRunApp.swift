import GuardianCore
import SwiftUI

/// Full monolith executable (Training + Mission surfaces) during cutover.
@main
struct GuardianHQRunApp: App {
    private static let _registerProduct: Void = {
        GuardianAppSessionBootstrap.registerActiveProduct(.fullHQ)
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = GuardianAppSession(product: .fullHQ)

    init() {
        _ = Self._registerProduct
        GuardianAppSessionBootstrap.bootstrapColdLaunch(for: .fullHQ)
    }

    var body: some Scene {
        GuardianBuiltAppScene(session: session)
    }
}
