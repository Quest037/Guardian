import Foundation

@MainActor
final class PaladinLiveDriveDomain: ObservableObject {
    struct LiveDriveAssistSnapshot: Equatable {
        var hasActiveSession: Bool
        var takeoverEligibleVehicleCount: Int

        static let empty = LiveDriveAssistSnapshot(hasActiveSession: false, takeoverEligibleVehicleCount: 0)
    }

    @Published private(set) var latestSnapshot: LiveDriveAssistSnapshot = .empty

    /// Stub entrypoint for LiveDrive + Paladin cooperation.
    /// TODO: Implement operator takeover / reserve-vehicle handover orchestration.
    func refreshLiveDriveAssistSnapshot(hasActiveSession: Bool, takeoverEligibleVehicleCount: Int) {
        latestSnapshot = LiveDriveAssistSnapshot(
            hasActiveSession: hasActiveSession,
            takeoverEligibleVehicleCount: max(0, takeoverEligibleVehicleCount)
        )
    }
}
