import Foundation

// MARK: - Reserve swap recipe stream correlation

/// Correlates a ``FleetRecipeRunner`` invocation with the **reserve** side of a Mission Control
/// swap-in (not the failing active airframe): mission run, task, vacancy roster row, reserve row
/// identity, pool berth when applicable, and resolved **fleet stream** ``vehicleID``.
///
/// Pass ``recipeRunnerSource(phase:)`` to ``FleetRecipeRunner/run(source:)`` so catalogue audit
/// lines disambiguate **missioncontrol.reserveSwap.*** from ``missionControl.preflightProbe`` /
/// ``vehicles.preflightProbe`` and from ad-hoc Vehicle Inspector runs.
struct MissionRunReserveRecipeRunnerCorrelation: Equatable, Sendable {

    /// Stable prefix segment inside ``recipeRunnerSource(phase:)``.
    static let recipeRunnerSourceNamespace = "missioncontrol.reserveSwap"

    let missionRunID: UUID
    let missionTaskID: UUID
    /// Roster assignment id for the **vacancy** (primary / wingman slot receiving the reserve).
    let vacancyAssignmentID: UUID
    /// Assignment id whose fleet binding defines the **reserve** stream: for pool rows this is
    /// ``MissionRunReservePoolSlot/id`` (see ``MissionRunAssignment/syntheticForReservePool``); for
    /// template ``.reserve`` rows it is the real ``MissionRunAssignment/id``.
    let reserveStreamAssignmentID: UUID
    /// Set when the reserve is a floating pool berth; `nil` for fixed roster reserve rows.
    let reservePoolSlotID: UUID?
    /// Resolved fleet stream id passed to ``FleetRecipeRunner/run(vehicleID:)``.
    let vehicleID: String

    /// Pool reserve: synthetic assignment id **equals** ``MissionRunReservePoolSlot/id``.
    static func floatingPoolReserve(
        missionRunID: UUID,
        missionTaskID: UUID,
        vacancyAssignmentID: UUID,
        poolSlot: MissionRunReservePoolSlot,
        vehicleID: String
    ) -> MissionRunReserveRecipeRunnerCorrelation {
        MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: missionRunID,
            missionTaskID: missionTaskID,
            vacancyAssignmentID: vacancyAssignmentID,
            reserveStreamAssignmentID: poolSlot.id,
            reservePoolSlotID: poolSlot.id,
            vehicleID: vehicleID
        )
    }

    /// Fixed template **reserve** roster row (not a pool berth).
    static func fixedRosterReserve(
        missionRunID: UUID,
        missionTaskID: UUID,
        vacancyAssignmentID: UUID,
        reserveAssignment: MissionRunAssignment,
        vehicleID: String
    ) -> MissionRunReserveRecipeRunnerCorrelation {
        MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: missionRunID,
            missionTaskID: missionTaskID,
            vacancyAssignmentID: vacancyAssignmentID,
            reserveStreamAssignmentID: reserveAssignment.id,
            reservePoolSlotID: nil,
            vehicleID: vehicleID
        )
    }

    /// `source` argument for ``FleetRecipeRunner/run(source:)`` — bounded, pipe-separated facts
    /// (``vehicleID`` pipe characters are flattened for log safety).
    func recipeRunnerSource(phase: MissionRunReserveSwapPipelinePhase) -> String {
        let pool = reservePoolSlotID?.uuidString ?? "-"
        let vid = Self.sanitizedVehicleIDFragment(vehicleID)
        return "\(Self.recipeRunnerSourceNamespace).\(phase.rawValue)|mr=\(missionRunID.uuidString)|mt=\(missionTaskID.uuidString)|vac=\(vacancyAssignmentID.uuidString)|rsv=\(reserveStreamAssignmentID.uuidString)|pool=\(pool)|v=\(vid)"
    }

    private static func sanitizedVehicleIDFragment(_ raw: String) -> String {
        raw.replacingOccurrences(of: "|", with: "_")
    }
}
