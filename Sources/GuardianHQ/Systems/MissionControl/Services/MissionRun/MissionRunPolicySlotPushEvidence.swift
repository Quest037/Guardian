import Foundation

/// §3 **push** evidence: map ``MissionRunIssuedCommand`` + fleet outcome to roster **slot** terminal states.
///
/// Only **policy-shaped** dispatches from Mission Control abort/complete wind-down issuers update lanes; other
/// catalogue/recipe traffic is ignored so staging / mission execute / reserve swap rows do not flip slot chips.
enum MissionRunPolicySlotPushEvidence {

    /// Issuers whose catalogue / recipe completions feed ``MissionRunAssignment/slotLifecycleLanes`` (README §3).
    static func issuerEligibleForSlotPolicyPushEvidence(_ issuerKey: String) -> Bool {
        issuerKey == MissionRunCommandIssuerKey.plannerAbort
            || issuerKey == MissionRunCommandIssuerKey.localOperator
            || issuerKey == MissionRunCommandIssuerKey.completePolicyWindDown
    }

    /// Terminal slot state to apply to **both** commanded and observed lanes, or `nil` when this outcome must not
    /// advance slot policy chips (e.g. mission clear **success** is an intermediate before RTL / move+park).
    static func terminalSlotStateIfAffected(issued: MissionRunIssuedCommand, success: Bool) -> MissionRunAssignmentSlotState? {
        guard issuerEligibleForSlotPolicyPushEvidence(issued.issuerKey) else { return nil }
        switch issued.dispatch {
        case .catalogue(let name, _):
            if name == .fleetVehicleDoMissionClear {
                return success ? nil : .policyFailed
            }
            if name == .fleetVehicleDoLoiter || name == .fleetVehicleDoPark {
                return success ? .policySucceeded : .policyFailed
            }
            return nil
        case .recipe(let name, _):
            let raw = name.rawValue
            if raw == "recipe.fleet.do.return.home"
                || raw == "recipe.fleet.do.move.point.park"
                || raw == "recipe.fleet.vehicle.do.park" {
                return success ? .policySucceeded : .policyFailed
            }
            return nil
        case .vehicleCommand:
            return nil
        }
    }
}
