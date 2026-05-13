import Foundation

// MARK: - Post-commit reserve swap handoff (stream resolution)

/// Normalised fleet storage keys on the **vacancy** roster row (new active after swap-in) and the **displaced** row
/// (pool berth synthetic row or bench ``.reserve`` assignment that still owns the former active’s binding).
struct MissionRunReserveSwapPostCommitStreamSnapshot: Equatable, Sendable {
    /// ``MissionRunAssignment/attachedFleetVehicleToken`` on the vacancy row (trimmed, non-empty).
    var vacancyFleetStorageKey: String
    /// Same for the displaced stream row (former reserve / pool berth row).
    var displacedFleetStorageKey: String
}

enum MissionRunReserveSwapPostCommitResolveOutcome: Equatable, Sendable {
    case resolved(MissionRunReserveSwapPostCommitStreamSnapshot)
    case missingVacancyAssignment
    case missingDisplacedStreamAssignment
    case vacancyFleetTokenMissing
    case displacedFleetTokenMissing
    case identicalFleetBindingsAfterCommit

    var logDetailFragment: String {
        switch self {
        case .resolved(let snap):
            return "newActiveToken=\(snap.vacancyFleetStorageKey) displacedActiveToken=\(snap.displacedFleetStorageKey)"
        case .missingVacancyAssignment:
            return "vacancy assignment row missing"
        case .missingDisplacedStreamAssignment:
            return "displaced stream assignment row missing"
        case .vacancyFleetTokenMissing:
            return "vacancy row has no fleet token after commit"
        case .displacedFleetTokenMissing:
            return "displaced stream row has no fleet token after commit"
        case .identicalFleetBindingsAfterCommit:
            return "vacancy and displaced rows share the same fleet token after commit"
        }
    }
}

/// Pure resolver for post–roster-commit / post–plan-recompile roster state (``MissionRosterReservesToDo.md`` executor item 1).
enum MissionRunReserveSwapPostCommitStreamResolver: Sendable {

    private static func normaliseFleetStorageKey(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// - Parameters:
    ///   - displacedStreamAssignmentID: For fixed template reserve, the bench ``.reserve`` assignment id; for floating pool, equals the pool berth ``MissionRunReservePoolSlot/id`` (same as ``MissionRunReserveRecipeRunnerCorrelation/reservePoolSlotID`` when set).
    ///   - floatingReservePool: When ``floatingReservePoolSlotID`` is non-nil, the displaced fleet binding is read from this pool’s matching entry instead of ``assignments``.
    ///   - floatingReservePoolSlotID: When non-nil, selects the **floating** displaced stream (pool berth); when nil, the displaced stream is resolved from ``assignments`` only.
    static func resolve(
        assignments: [MissionRunAssignment],
        vacancyAssignmentID: UUID,
        displacedStreamAssignmentID: UUID,
        floatingReservePool: MissionRunReservePool? = nil,
        floatingReservePoolSlotID: UUID? = nil
    ) -> MissionRunReserveSwapPostCommitResolveOutcome {
        guard let vacancy = assignments.first(where: { $0.id == vacancyAssignmentID }) else {
            return .missingVacancyAssignment
        }
        let vacKey = normaliseFleetStorageKey(vacancy.attachedFleetVehicleToken)
        if vacKey.isEmpty { return .vacancyFleetTokenMissing }

        let disKey: String
        if let poolSlotID = floatingReservePoolSlotID {
            guard let pool = floatingReservePool else {
                return .missingDisplacedStreamAssignment
            }
            guard let slot = pool.entries.first(where: { $0.id == poolSlotID }) else {
                return .missingDisplacedStreamAssignment
            }
            disKey = normaliseFleetStorageKey(slot.attachedFleetVehicleToken)
        } else {
            guard let displaced = assignments.first(where: { $0.id == displacedStreamAssignmentID }) else {
                return .missingDisplacedStreamAssignment
            }
            disKey = normaliseFleetStorageKey(displaced.attachedFleetVehicleToken)
        }
        if disKey.isEmpty { return .displacedFleetTokenMissing }
        if vacKey == disKey { return .identicalFleetBindingsAfterCommit }
        return .resolved(
            MissionRunReserveSwapPostCommitStreamSnapshot(
                vacancyFleetStorageKey: vacKey,
                displacedFleetStorageKey: disKey
            )
        )
    }
}
