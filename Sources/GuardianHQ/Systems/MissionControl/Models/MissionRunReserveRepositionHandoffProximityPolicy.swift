import Foundation

// MARK: - Reposition handoff proximity + timeout

/// Locked **v1** “close enough” tolerances and **reposition phase** timeout before swap-in advances past **move reserve**
/// (``MissionRosterReservesToDo.md`` — timeout / proximity).
///
/// **All vehicle classes:** defaults are class-agnostic magnitudes; the executor compares hub / pose telemetry for
/// the **reserve** vs the handoff anchor (active hub, rally point, or formation target) and maps **vertical**
/// separation per class (e.g. AGL for multirotor / fixed-wing, terrain-relative or surrogate axis for UGV / surface
/// assets when that is what the stack exposes).
enum MissionRunReserveRepositionHandoffProximityPolicy {

    /// Hub-to-hub or hub-to-anchor horizontal distance (metres) at or below which reposition is **complete**.
    static let defaultHorizontalCloseEnoughMeters: Double = 40

    /// Vertical separation vs the handoff anchor (metres). Interpretation is **executor-defined per** ``FleetVehicleType``.
    static let defaultVerticalCloseEnoughMeters: Double = 25

    /// Maximum wall-clock duration for the reposition phase before treating it as failed (retry / next candidate / escalate).
    static let defaultRepositionPhaseTimeoutSeconds: TimeInterval = 600

    struct LockedDefaultsValidation: Equatable, Sendable {
        var isValid: Bool
        var rejectionReason: String?

        static func valid() -> LockedDefaultsValidation {
            LockedDefaultsValidation(isValid: true, rejectionReason: nil)
        }

        static func rejected(_ reason: String) -> LockedDefaultsValidation {
            LockedDefaultsValidation(isValid: false, rejectionReason: reason)
        }
    }

    /// Sanity check for catalogue / tests — production constants must stay strictly positive.
    static func validateLockedDefaults() -> LockedDefaultsValidation {
        guard defaultHorizontalCloseEnoughMeters > 0 else {
            return .rejected("defaultHorizontalCloseEnoughMeters must be > 0.")
        }
        guard defaultVerticalCloseEnoughMeters > 0 else {
            return .rejected("defaultVerticalCloseEnoughMeters must be > 0.")
        }
        guard defaultRepositionPhaseTimeoutSeconds > 0 else {
            return .rejected("defaultRepositionPhaseTimeoutSeconds must be > 0.")
        }
        return .valid()
    }
}
