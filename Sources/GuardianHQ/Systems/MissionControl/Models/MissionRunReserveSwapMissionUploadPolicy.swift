import Foundation

// MARK: - Reserve swap mission upload (slice policy)

/// Which MAVLink mission payload is uploaded to the **reserve** during live swap-in **mission upload**
/// (policy lives in this file; tracker mechanics in ``MissionRosterReservesToDo.md``).
enum MissionRunReserveMissionUploadSliceKind: String, Equatable, Codable, CaseIterable, Sendable {
    /// Upload the **full** compiled task mission for the vacancy’s task (same envelope as normal MC
    /// task mission start / staging upload for that task path).
    case fullTaskMission
    /// Upload only the **tail** from the active airframe’s last-known mission cursor (requires a
    /// validated ``MissionRunReserveMissionPartialCursor`` aligned with hub MAVLink mission progress).
    case partialFromActiveExecutionCursor
}

/// Snapshot of active progress used when ``MissionRunReserveMissionUploadSliceKind/partialFromActiveExecutionCursor``
/// is selected. Fields mirror MC-R progress inputs (``hub.missionProgressCurrent`` / ``hub.missionProgressTotal``).
struct MissionRunReserveMissionPartialCursor: Equatable, Sendable {
    /// Current mission item index from telemetry (0-based is typical for MAVLink mission_seq).
    var missionProgressCurrent: Int?
    /// Total mission items reported on the active vehicle (must be ≥ 1 when partial upload is allowed).
    var missionProgressTotal: Int?
    /// Optional task cycle index on the run when handoff must preserve cycle semantics.
    var taskCycleIndex: Int?
}

// MARK: - Active synchronisation (mission upload to reserve)

/// How the **vacancy (active)** airframe is coordinated while the **reserve** receives a MAVLink mission upload.
enum MissionRunReserveMissionUploadActiveSynchronisationKind: String, Equatable, Codable, CaseIterable, Sendable {
    /// Reserve mission upload proceeds **without** a Mission Control–enforced hold on the active pattern;
    /// MAVLink mission list races between active and reserve are possible — use only when RoE / operator
    /// explicitly accepts that risk (time-critical swap).
    case concurrentActiveNoHold
    /// Hold the active task’s executing pattern (whole-run **pause** or task-scoped **hold** — executor wiring
    /// TBD) until the reserve upload phase completes or the swap aborts; deterministic mission state on the active.
    case hardPauseActiveUntilUploadCompletes
}

// MARK: - Post-upload verification (reserve)

/// How the swap pipeline proves the **reserve** received the intended MAVLink mission after upload.
enum MissionRunReserveMissionUploadVerificationKind: String, Equatable, Codable, CaseIterable, Sendable {
    /// Download or query mission count on the reserve and compare to the expected item count from the compile/upload payload.
    case missionItemCountReadback
    /// Compare a deterministic **content hash** of the mission items envelope (executor must use the same hash surface as upload encoding).
    case missionPlanContentHashMatch
    /// Run a catalogue **recipe** that gates “mission ready / startable” on the reserve stream (recipe name supplied in ``MissionRunReserveMissionUploadVerificationExpectation``).
    case recipeBasedMissionReadyProbe
}

/// Inputs required **before** running the selected ``MissionRunReserveMissionUploadVerificationKind`` gate (executor fills readback results separately).
struct MissionRunReserveMissionUploadVerificationExpectation: Equatable, Sendable {
    var expectedMissionItemCount: Int?
    var expectedContentHash: String?
    /// Raw `recipe.*` name registered in ``FleetRecipesCatalogue`` when using ``MissionRunReserveMissionUploadVerificationKind/recipeBasedMissionReadyProbe``.
    var missionReadyRecipeRaw: String?

    init(
        expectedMissionItemCount: Int? = nil,
        expectedContentHash: String? = nil,
        missionReadyRecipeRaw: String? = nil
    ) {
        self.expectedMissionItemCount = expectedMissionItemCount
        self.expectedContentHash = expectedContentHash
        self.missionReadyRecipeRaw = missionReadyRecipeRaw
    }
}

// MARK: - Mission upload failure (reserve swap-in)

/// What may happen when mission **upload** or **verification** fails on the **reserve** during swap-in.
enum MissionRunReserveMissionUploadFailureDispositionKind: String, Equatable, Codable, CaseIterable, Sendable {
    /// Do not advance later swap phases (reposition, roster commit) until upload + verification succeed;
    /// use ``MissionRunReserveSwapFailureBranchPolicy`` for retries / next candidate / escalate / abort.
    case strictBlockUntilUploadAndVerificationSucceed
    /// Permit a **degraded** handoff only after an operator attestation is recorded (UI / confirm overlay wiring TBD).
    case allowDegradedHandoffAfterOperatorConfirmation
}

/// Operator evidence required when ``MissionRunReserveMissionUploadFailureDispositionKind/allowDegradedHandoffAfterOperatorConfirmation`` is active.
struct MissionRunReserveMissionUploadDegradedHandoffAttestation: Equatable, Sendable {
    /// Short, non-empty operator-facing summary stored on audit / run log when degraded path is taken.
    var acknowledgmentSummary: String
    var missionRunID: UUID
    var at: Date

    init(acknowledgmentSummary: String, missionRunID: UUID, at: Date = Date()) {
        self.acknowledgmentSummary = acknowledgmentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.missionRunID = missionRunID
        self.at = at
    }
}

/// Locked **v1** rules for reserve **mission slice** selection (full vs partial).
enum MissionRunReserveSwapMissionUploadPolicy {

    /// Default: never imply a successful mission state on the reserve without upload + verification success.
    static let defaultUploadFailureDispositionKind: MissionRunReserveMissionUploadFailureDispositionKind = .strictBlockUntilUploadAndVerificationSucceed

    /// Default post-upload proof: count readback is implemented broadly across stacks before hash/recipe gates ship for swap-in.
    static let defaultUploadVerificationKind: MissionRunReserveMissionUploadVerificationKind = .missionItemCountReadback

    /// Default synchronisation while the reserve is in **mission upload**: prefer deterministic active
    /// mission state over minimum time-to-replace.
    static let defaultActiveSynchronisationKind: MissionRunReserveMissionUploadActiveSynchronisationKind = .hardPauseActiveUntilUploadCompletes

    /// Default when the swap pipeline has **not** completed a verified partial cursor handshake with the active FC.
    static let defaultSliceKind: MissionRunReserveMissionUploadSliceKind = .fullTaskMission

    struct UploadSliceValidation: Equatable, Sendable {
        var allowsDispatch: Bool
        var rejectionReason: String?

        static func ok() -> UploadSliceValidation {
            UploadSliceValidation(allowsDispatch: true, rejectionReason: nil)
        }

        static func rejected(_ reason: String) -> UploadSliceValidation {
            UploadSliceValidation(allowsDispatch: false, rejectionReason: reason)
        }
    }

    /// Whether the chosen slice + cursor may proceed to mission encoding / upload dispatch.
    static func validate(slice: MissionRunReserveMissionUploadSliceKind, partialCursor: MissionRunReserveMissionPartialCursor?) -> UploadSliceValidation {
        switch slice {
        case .fullTaskMission:
            return .ok()
        case .partialFromActiveExecutionCursor:
            guard let partialCursor else {
                return .rejected("Partial mission upload requires a partial cursor snapshot.")
            }
            guard let cur = partialCursor.missionProgressCurrent, let tot = partialCursor.missionProgressTotal else {
                return .rejected("Partial mission upload requires missionProgressCurrent and missionProgressTotal.")
            }
            guard tot >= 1 else {
                return .rejected("Partial mission upload requires missionProgressTotal ≥ 1.")
            }
            guard cur >= 0, cur < tot else {
                return .rejected("Partial mission upload requires 0 ≤ missionProgressCurrent < missionProgressTotal.")
            }
            return .ok()
        }
    }

    struct UploadVerificationReadiness: Equatable, Sendable {
        var isReady: Bool
        var rejectionReason: String?

        static func ready() -> UploadVerificationReadiness {
            UploadVerificationReadiness(isReady: true, rejectionReason: nil)
        }

        static func rejected(_ reason: String) -> UploadVerificationReadiness {
            UploadVerificationReadiness(isReady: false, rejectionReason: reason)
        }
    }

    /// Whether prerequisites are met to **schedule** the verification gate (telemetry compare happens later).
    static func validateVerificationReadiness(
        kind: MissionRunReserveMissionUploadVerificationKind,
        expectation: MissionRunReserveMissionUploadVerificationExpectation?
    ) -> UploadVerificationReadiness {
        switch kind {
        case .missionItemCountReadback:
            guard let n = expectation?.expectedMissionItemCount else {
                return .rejected("Mission item count readback requires expectedMissionItemCount.")
            }
            guard n >= 0 else {
                return .rejected("expectedMissionItemCount must be ≥ 0.")
            }
            return .ready()
        case .missionPlanContentHashMatch:
            guard let h = expectation?.expectedContentHash?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty else {
                return .rejected("Mission plan hash verification requires a non-empty expectedContentHash.")
            }
            return .ready()
        case .recipeBasedMissionReadyProbe:
            guard let raw = expectation?.missionReadyRecipeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return .rejected("Recipe-based mission verification requires missionReadyRecipeRaw.")
            }
            guard FleetRecipeName.isValidRawValue(raw) else {
                return .rejected("missionReadyRecipeRaw is not a valid recipe name.")
            }
            return .ready()
        }
    }

    /// Whether an operator may invoke the **degraded** mission-handoff branch for this failure policy.
    static func validateDegradedHandoffPrerequisites(
        failureDisposition: MissionRunReserveMissionUploadFailureDispositionKind,
        operatorAttestation: MissionRunReserveMissionUploadDegradedHandoffAttestation?
    ) -> UploadVerificationReadiness {
        switch failureDisposition {
        case .strictBlockUntilUploadAndVerificationSucceed:
            return .rejected("Degraded mission handoff is not permitted under strict upload failure policy.")
        case .allowDegradedHandoffAfterOperatorConfirmation:
            guard let a = operatorAttestation else {
                return .rejected("Degraded handoff requires operator attestation.")
            }
            guard !a.acknowledgmentSummary.isEmpty else {
                return .rejected("Operator attestation summary must be non-empty.")
            }
            return .ready()
        }
    }
}
