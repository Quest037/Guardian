import Foundation

// MARK: - Body

/// The executable spec for a recipe: ordered step list + entry point + overall
/// budget. Hangs off ``FleetRecipeDescriptor/body`` as an optional field — v1
/// descriptors can register without a body so the Stage C subsystem rollout can
/// land descriptors and bodies independently.
///
/// **Steps are ordered**: the runner uses array order for `.continueToNextStep`
/// resolution and for the failing-step path reported on recipe failure.
///
/// **Overall budget** (``overallBudgetSeconds``) is the hard wall-clock cap on the
/// entire run, applied by the runner. Step-level command timeouts and retry
/// backoffs draw from this budget; once the cap is hit the runner fails the
/// recipe with `.timeout`.
struct FleetRecipeBody: Equatable, Hashable, Sendable {

    /// Default overall budget when the body omits its own — chosen to be generous
    /// for calibration recipes while still bounded enough to surface hung steps.
    static let defaultOverallBudgetSeconds: TimeInterval = 60

    /// Hard cap on the overall budget. Parser rejects bodies that exceed this.
    /// 600s is enough for the longest realistic Stage C calibration flow.
    static let maximumOverallBudgetSeconds: TimeInterval = 600

    /// Step that runs first.
    let entryStepID: FleetRecipeStepID

    /// Ordered step list. Always non-empty after parsing.
    let steps: [FleetRecipeStep]

    /// Wall-clock cap for the entire run.
    let overallBudgetSeconds: TimeInterval

    init(
        entryStepID: FleetRecipeStepID,
        steps: [FleetRecipeStep],
        overallBudgetSeconds: TimeInterval = FleetRecipeBody.defaultOverallBudgetSeconds
    ) {
        self.entryStepID = entryStepID
        self.steps = steps
        self.overallBudgetSeconds = overallBudgetSeconds
    }

    // MARK: Lookup

    func step(withID id: FleetRecipeStepID) -> FleetRecipeStep? {
        steps.first(where: { $0.id == id })
    }

    func index(ofStepWithID id: FleetRecipeStepID) -> Int? {
        steps.firstIndex(where: { $0.id == id })
    }
}

// MARK: - Codable

extension FleetRecipeBody: Codable {

    private enum CodingKeys: String, CodingKey {
        case entryStepID
        case steps
        case overallBudgetSeconds
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entryStepID = try c.decode(FleetRecipeStepID.self, forKey: .entryStepID)
        let steps = try c.decode([FleetRecipeStep].self, forKey: .steps)
        let budget = try c.decodeIfPresent(TimeInterval.self, forKey: .overallBudgetSeconds)
            ?? FleetRecipeBody.defaultOverallBudgetSeconds
        self.init(entryStepID: entryStepID, steps: steps, overallBudgetSeconds: budget)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryStepID, forKey: .entryStepID)
        try c.encode(steps, forKey: .steps)
        try c.encode(overallBudgetSeconds, forKey: .overallBudgetSeconds)
    }
}
