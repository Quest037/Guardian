import Foundation

/// Per-process launch hooks before ``GuardianAppSession`` is constructed.
@MainActor
public enum GuardianAppSessionBootstrap {
    /// Set in each executable's `@main` `init` before ``AppDelegate`` runs.
    public private(set) static var activeProduct: GuardianAppProduct = .fullHQ

    public static func bootstrapColdLaunch(for product: GuardianAppProduct) {
        activeProduct = product
        GuardianSitlOrphanBlitz.kickoffFromColdLaunch()
        GuardianRos2OrphanBlitz.kickoffFromColdLaunch()
        if product.includesGazeboSimulation {
            GuardianGazeboOrphanBlitz.kickoffFromColdLaunch()
        }
    }

    /// Same product lock as ``GuardianAppSession/init(product:)`` for dock icon before the session exists.
    public static func registerActiveProduct(_ product: GuardianAppProduct) {
        activeProduct = product
    }
}
