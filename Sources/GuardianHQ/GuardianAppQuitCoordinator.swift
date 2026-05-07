import AppKit
import Foundation

/// Dev-oriented full teardown on macOS quit: SITL children (PX4 / ArduPilot) then every `mavsdk_server` session.
@MainActor
final class GuardianAppQuitCoordinator {
    static let shared = GuardianAppQuitCoordinator()

    private weak var fleet: FleetLinkService?
    private weak var sitl: SitlService?

    private init() {}

    /// Called from `FleetLinkService` / `SitlService` init so quit teardown works even before any view `onAppear`.
    func noteFleetLinkServiceCreated(_ service: FleetLinkService) {
        fleet = service
    }

    func noteSitlServiceCreated(_ service: SitlService) {
        sitl = service
    }

    func teardownForApplicationQuit() {
        sitl?.stopAllForApplicationQuit()
        fleet?.teardownAllForApplicationQuit()
    }
}
