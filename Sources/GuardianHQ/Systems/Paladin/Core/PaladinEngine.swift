import Combine
import Foundation

/// Core entry point for Paladin domains.
///
/// Paladin is an always-on app subsystem; domains stay mostly idle until invoked by
/// orchestrators (e.g. Mission Control running a mission).
@MainActor
final class PaladinEngine: ObservableObject {
    static let shared = PaladinEngine()

    let missionControlDomain = PaladinMissionControlDomain()
    let missionsDomain = PaladinMissionsDomain()
    let liveDriveDomain = PaladinLiveDriveDomain()
    let fleetDomain = PaladinFleetDomain()

    private init() {}

    // MARK: - Other domain handles (stubs)

    func missionControlDomainBridge() -> PaladinMissionControlDomain {
        missionControlDomain
    }

    func missionDomain() -> PaladinMissionsDomain {
        missionsDomain
    }

    func liveDriveDomainBridge() -> PaladinLiveDriveDomain {
        liveDriveDomain
    }

    func fleetDomainBridge() -> PaladinFleetDomain {
        fleetDomain
    }
}
