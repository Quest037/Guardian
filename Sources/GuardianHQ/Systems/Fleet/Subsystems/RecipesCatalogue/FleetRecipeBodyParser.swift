import Foundation

// MARK: - Parse error

/// Structural problem detected by ``FleetRecipeBodyParser`` during JSON decode or
/// post-decode validation. The parser returns **every** issue it finds in a single
/// pass so authoring UIs can surface a complete picture instead of a one-error-at-a-time
/// loop.
enum FleetRecipeBodyParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `Codable`-level decode failed (mistyped JSON, unknown discriminator, etc.).
    /// The underlying error is preserved as a string because the lower-level Foundation
    /// errors aren't `Equatable`.
    case decodeFailed(detail: String)

    /// The body declared zero steps.
    case noSteps

    /// Two or more steps share the same ID.
    case duplicateStepID(FleetRecipeStepID)

    /// `entryStepID` does not exist among `steps`.
    case entryStepNotFound(FleetRecipeStepID)

    /// A step's matcher list is empty.
    case stepHasNoMatchers(FleetRecipeStepID)

    /// `.any` matcher appeared somewhere other than the last position in a step's
    /// matcher list. Multiple `.any` matchers are likewise rejected.
    case anyMatcherMustBeLast(FleetRecipeStepID)

    /// A `.branch(stepID:)` outcome references a step that doesn't exist in the
    /// same body.
    case branchTargetNotFound(stepID: FleetRecipeStepID, fromStep: FleetRecipeStepID)

    /// A `.invokeCommand(...)` step references a command that isn't registered in
    /// ``FleetCommandsCatalogue``.
    case invokedCommandNotRegistered(FleetCommandName)

    /// A `.invokeRecipe(...)` step references a recipe that isn't registered in
    /// ``FleetRecipesCatalogue``.
    case invokedRecipeNotRegistered(FleetRecipeName)

    /// A `.invokeRecipe(...)` step references a recipe whose body itself contains
    /// an `.invokeRecipe(...)` step. Enforces the locked 1-level composition limit.
    case invokedRecipeBodyExceedsDepthLimit(parent: FleetRecipeName, child: FleetRecipeName)

    /// A `.stringMatches(regex:)` predicate's pattern failed to compile.
    case predicateRegexInvalid(pattern: String, fromStep: FleetRecipeStepID)

    /// `overallBudgetSeconds` exceeds ``FleetRecipeBody/maximumOverallBudgetSeconds``.
    case overallBudgetExceedsCap(declared: TimeInterval, cap: TimeInterval)

    /// `overallBudgetSeconds` is non-positive.
    case overallBudgetNotPositive(declared: TimeInterval)

    /// A step's retry override exceeds the recipe-wide caps and the descriptor
    /// did not set `relaxRetryCaps = true`.
    case stepRetryPolicyExceedsCaps(stepID: FleetRecipeStepID, detail: String)

    /// A step parameter references a caller-supplied recipe parameter that the
    /// owning descriptor did not declare.
    case stepParameterReferenceNotDeclared(stepID: FleetRecipeStepID, parameterName: String)

    /// A step parameter reference resolves to a descriptor parameter whose type
    /// is incompatible with the target command / child recipe parameter.
    case stepParameterReferenceTypeMismatch(
        stepID: FleetRecipeStepID,
        parameterName: String,
        expected: FleetRecipeParameterType,
        actual: FleetRecipeParameterType
    )

    var description: String {
        switch self {
        case .decodeFailed(let detail):
            return "decode failed: \(detail)"
        case .noSteps:
            return "body has no steps"
        case .duplicateStepID(let id):
            return "duplicate step id '\(id.rawValue)'"
        case .entryStepNotFound(let id):
            return "entryStepID '\(id.rawValue)' does not exist among steps"
        case .stepHasNoMatchers(let id):
            return "step '\(id.rawValue)' has no matchers"
        case .anyMatcherMustBeLast(let id):
            return "step '\(id.rawValue)' uses `.any` matcher in a non-final position (or more than once)"
        case .branchTargetNotFound(let target, let from):
            return "step '\(from.rawValue)' branches to non-existent step '\(target.rawValue)'"
        case .invokedCommandNotRegistered(let name):
            return "command '\(name.rawValue)' is not registered in FleetCommandsCatalogue"
        case .invokedRecipeNotRegistered(let name):
            return "recipe '\(name.rawValue)' is not registered in FleetRecipesCatalogue"
        case .invokedRecipeBodyExceedsDepthLimit(let parent, let child):
            return "recipe '\(parent.rawValue)' cannot invoke '\(child.rawValue)' because the child itself invokes other recipes (1-level depth limit)"
        case .predicateRegexInvalid(let pattern, let step):
            return "step '\(step.rawValue)' uses uncompilable regex pattern '\(pattern)'"
        case .overallBudgetExceedsCap(let declared, let cap):
            return "overallBudgetSeconds \(declared)s exceeds cap \(cap)s"
        case .overallBudgetNotPositive(let declared):
            return "overallBudgetSeconds \(declared)s is not positive"
        case .stepRetryPolicyExceedsCaps(let id, let detail):
            return "step '\(id.rawValue)' retry policy exceeds caps: \(detail)"
        case .stepParameterReferenceNotDeclared(let id, let name):
            return "step '\(id.rawValue)' references undeclared recipe parameter '\(name)'"
        case .stepParameterReferenceTypeMismatch(let id, let name, let expected, let actual):
            return "step '\(id.rawValue)' parameter reference '\(name)' type \(actual.rawValue) does not match target parameter type \(expected.rawValue)"
        }
    }
}

// MARK: - Error bundle

/// Bundle of parse errors surfaced by ``FleetRecipeBodyParser/parse(jsonData:against:recipes:commands:)``.
///
/// Exists because `Result.Failure` must itself conform to `Error`. The parser
/// deliberately reports **every** structural problem in one pass, so the natural
/// shape is "many errors at once"; this wrapper makes that compatible with `Result`
/// without flattening the diagnostic detail authoring UIs need.
struct FleetRecipeBodyParseErrors: Error, Equatable, Sendable, CustomStringConvertible {
    let errors: [FleetRecipeBodyParseError]

    init(_ errors: [FleetRecipeBodyParseError]) {
        self.errors = errors
    }

    var description: String {
        errors.map(\.description).joined(separator: "; ")
    }
}

// MARK: - Parser

/// Decoder + structural validator for ``FleetRecipeBody``.
///
/// Two layers:
/// 1. ``decode(jsonData:)`` runs Foundation's JSON decoder over the body JSON shape.
///    Decode-level failures surface as ``FleetRecipeBodyParseError/decodeFailed(detail:)``.
/// 2. ``validate(_:against:registry:)`` runs the post-decode structural rules
///    (step-ID uniqueness, branch targets exist, registered command/recipe
///    references, 1-level recipe composition, regex compile, budget caps, etc.).
///    Returns **every** error in one pass.
///
/// ``parse(jsonData:against:registry:)`` is the composite happy-path entry that
/// runs both layers.
@MainActor
enum FleetRecipeBodyParser {

    /// Decode a body from JSON without any structural validation.
    static func decode(jsonData: Data) -> Result<FleetRecipeBody, FleetRecipeBodyParseError> {
        let decoder = JSONDecoder()
        do {
            let body = try decoder.decode(FleetRecipeBody.self, from: jsonData)
            return .success(body)
        } catch {
            return .failure(.decodeFailed(detail: String(describing: error)))
        }
    }

    /// Structural validation against the two live registries plus the supplied
    /// descriptor's `relaxRetryCaps` flag.
    static func validate(
        _ body: FleetRecipeBody,
        against descriptor: FleetRecipeDescriptor,
        recipes: FleetRecipesCatalogue,
        commands: FleetCommandsCatalogue
    ) -> [FleetRecipeBodyParseError] {

        var errors: [FleetRecipeBodyParseError] = []

        // Step-set checks.
        if body.steps.isEmpty {
            errors.append(.noSteps)
        }

        var seenIDs: Set<FleetRecipeStepID> = []
        for step in body.steps {
            if seenIDs.contains(step.id) {
                errors.append(.duplicateStepID(step.id))
            } else {
                seenIDs.insert(step.id)
            }
        }

        if !body.steps.isEmpty, body.step(withID: body.entryStepID) == nil {
            errors.append(.entryStepNotFound(body.entryStepID))
        }

        // Budget checks.
        if body.overallBudgetSeconds <= 0 {
            errors.append(.overallBudgetNotPositive(declared: body.overallBudgetSeconds))
        }
        if body.overallBudgetSeconds > FleetRecipeBody.maximumOverallBudgetSeconds {
            errors.append(.overallBudgetExceedsCap(
                declared: body.overallBudgetSeconds,
                cap: FleetRecipeBody.maximumOverallBudgetSeconds
            ))
        }

        // Per-step checks.
        for step in body.steps {
            errors.append(contentsOf: validateMatcherList(step.matchers, stepID: step.id, body: body))
            errors.append(contentsOf: validatePredicateRegexes(in: step.matchers, stepID: step.id))

            switch step {
            case .invokeCommand(let id, let command, let stepParameters, let retry, _):
                if let commandDescriptor = commands.descriptor(for: command) {
                    errors.append(contentsOf: validateParameterReferences(
                        stepParameters,
                        stepID: id,
                        descriptorParameters: descriptor.parameters,
                        targetParameters: commandDescriptor.parameters.map { FleetRecipeParameterDeclaration(
                            name: $0.name,
                            type: FleetRecipeParameterType(commandType: $0.type),
                            required: $0.isRequired,
                            allowedStringValues: $0.allowedStringValues,
                            humanLabel: $0.humanLabel
                        ) }
                    ))
                } else {
                    errors.append(.invokedCommandNotRegistered(command))
                }
                if let retry, !descriptor.relaxRetryCaps {
                    let violations = FleetRecipeRetryPolicy.violations(for: retry)
                    if !violations.isEmpty {
                        let detail = violations.map(\.description).joined(separator: "; ")
                        errors.append(.stepRetryPolicyExceedsCaps(stepID: id, detail: detail))
                    }
                }
            case .invokeRecipe(let id, let recipe, let stepParameters, _):
                guard let child = recipes.descriptor(for: recipe) else {
                    errors.append(.invokedRecipeNotRegistered(recipe))
                    continue
                }
                errors.append(contentsOf: validateParameterReferences(
                    stepParameters,
                    stepID: id,
                    descriptorParameters: descriptor.parameters,
                    targetParameters: child.parameters
                ))
                if child.bodyInvokesAnyRecipe {
                    errors.append(.invokedRecipeBodyExceedsDepthLimit(
                        parent: descriptor.name,
                        child: recipe
                    ))
                }
            }
        }

        return errors
    }

    /// Composite happy-path entry: decode JSON, then validate against registries.
    /// Returns the parsed body only when both phases succeed.
    static func parse(
        jsonData: Data,
        against descriptor: FleetRecipeDescriptor,
        recipes: FleetRecipesCatalogue,
        commands: FleetCommandsCatalogue
    ) -> Result<FleetRecipeBody, FleetRecipeBodyParseErrors> {
        switch decode(jsonData: jsonData) {
        case .failure(let error):
            return .failure(FleetRecipeBodyParseErrors([error]))
        case .success(let body):
            let errors = validate(body, against: descriptor, recipes: recipes, commands: commands)
            return errors.isEmpty ? .success(body) : .failure(FleetRecipeBodyParseErrors(errors))
        }
    }

    // MARK: Helpers

    private static func validateMatcherList(
        _ matchers: [FleetRecipeStepMatcher],
        stepID: FleetRecipeStepID,
        body: FleetRecipeBody
    ) -> [FleetRecipeBodyParseError] {
        var out: [FleetRecipeBodyParseError] = []

        if matchers.isEmpty {
            out.append(.stepHasNoMatchers(stepID))
            return out
        }

        // `.any` matcher rule: at most one occurrence, must be last.
        var sawAnyAt: Int?
        for (idx, matcher) in matchers.enumerated() {
            if case .any = matcher.when {
                if sawAnyAt != nil {
                    out.append(.anyMatcherMustBeLast(stepID))
                    break
                }
                sawAnyAt = idx
            }
        }
        if let sawAnyAt, sawAnyAt != matchers.count - 1 {
            out.append(.anyMatcherMustBeLast(stepID))
        }

        // Branch target existence.
        for matcher in matchers {
            if case .branch(let targetID) = matcher.then {
                if body.step(withID: targetID) == nil {
                    out.append(.branchTargetNotFound(stepID: targetID, fromStep: stepID))
                }
            }
        }

        return out
    }

    private static func validatePredicateRegexes(
        in matchers: [FleetRecipeStepMatcher],
        stepID: FleetRecipeStepID
    ) -> [FleetRecipeBodyParseError] {
        var out: [FleetRecipeBodyParseError] = []
        for matcher in matchers {
            let predicate: FleetRecipePayloadPredicate?
            switch matcher.when {
            case .success(let p): predicate = p
            case .data(let p): predicate = p
            default: predicate = nil
            }
            guard let predicate else { continue }
            if !predicate.isStructurallyValid {
                if case .stringMatches(let pattern) = predicate {
                    out.append(.predicateRegexInvalid(pattern: pattern, fromStep: stepID))
                }
            }
        }
        return out
    }

    private static func validateParameterReferences(
        _ parameters: FleetRecipeParameters,
        stepID: FleetRecipeStepID,
        descriptorParameters: [FleetRecipeParameterDeclaration],
        targetParameters: [FleetRecipeParameterDeclaration]
    ) -> [FleetRecipeBodyParseError] {
        let descriptorByName = Dictionary(uniqueKeysWithValues: descriptorParameters.map { ($0.name, $0) })
        let targetByName = Dictionary(uniqueKeysWithValues: targetParameters.map { ($0.name, $0) })

        var out: [FleetRecipeBodyParseError] = []
        for (targetParameterName, value) in parameters.values {
            guard case .reference(let referencedName) = value else { continue }
            guard let descriptorDeclaration = descriptorByName[referencedName] else {
                out.append(.stepParameterReferenceNotDeclared(
                    stepID: stepID,
                    parameterName: referencedName
                ))
                continue
            }
            guard let targetDeclaration = targetByName[targetParameterName] else {
                continue
            }
            if !typesAreCompatible(expected: targetDeclaration.type, actual: descriptorDeclaration.type) {
                out.append(.stepParameterReferenceTypeMismatch(
                    stepID: stepID,
                    parameterName: referencedName,
                    expected: targetDeclaration.type,
                    actual: descriptorDeclaration.type
                ))
            }
        }
        return out
    }

    private static func typesAreCompatible(
        expected: FleetRecipeParameterType,
        actual: FleetRecipeParameterType
    ) -> Bool {
        switch (expected, actual) {
        case (.double, .integer):
            return true
        default:
            return expected == actual
        }
    }
}

private extension FleetRecipeParameterType {
    init(commandType: FleetCommandParameterType) {
        switch commandType {
        case .bool: self = .bool
        case .integer: self = .integer
        case .double: self = .double
        case .string: self = .string
        case .stringList: self = .stringList
        }
    }
}
