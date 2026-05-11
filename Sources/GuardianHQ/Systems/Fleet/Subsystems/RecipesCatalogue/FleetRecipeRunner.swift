import Combine
import Foundation
import os

// MARK: - Command invoker injection

/// Function shape the runner uses to dispatch a single Layer 0 command. The
/// production wiring forwards to ``FleetCommandsCatalogue`` with the live link and
/// ``FleetCommandsCatalogue/invoke(_:parameters:vehicleID:source:fleetLink:timeout:invokingPluginID:)``
/// plugin argument set from the owning recipe's ``FleetRecipeDescriptor/pluginID``; tests inject stubs.
typealias FleetRecipeCommandInvoker = @MainActor (
    _ name: FleetCommandName,
    _ parameters: FleetCommandParameters,
    _ vehicleID: String,
    _ source: String,
    _ timeout: TimeInterval,
    _ invokingPluginID: GuardianPluginID?
) async -> FleetCommandResponse

// MARK: - Live-mission gate injection

/// Predicate returning `true` when `vehicleID` is currently bound to any
/// running / paused / recovery Mission Control run — i.e. the existing
/// "vehicle is in a live mission" primitive.
///
/// Production wiring (installed at app start by ``RootView``) routes through
/// ``MissionControlStore/isVehicleStreamUsedInLiveMission(vehicleID:fleetLink:sitl:)``
/// so the runner reuses the same primitive that today's preflight pipeline
/// honours. Tests inject deterministic stubs; leaving the property `nil`
/// disables gating altogether (sensible for the no-mission-control case).
typealias FleetRecipeLiveMissionGate = @MainActor (_ vehicleID: String) -> Bool

// MARK: - Runner

/// **Layer 1 — universal recipe runner.**
///
/// Drives a registered recipe's body end-to-end against a vehicle, applying the
/// step machine semantics declared in the DSL (`continue`/`branch`/`retry`/
/// `succeed`/`fail`/`escalate`) and surfacing a binary
/// ``FleetRecipeOutcome`` plus a per-step ``FleetRecipeAuditTrace``.
///
/// **Concurrency model:** one active run per vehicle. A second `run(...)` for a
/// vehicle that is already executing a recipe fails fast with a recognisable
/// `detail` string (locked decision: refuse on conflict, callers retry). Internal
/// `invokeRecipe` step expansions bypass the per-vehicle gate because they are
/// part of the parent run's accounting.
///
/// **Cancellation:** ``cancel(vehicleID:)`` / ``cancel(runID:)`` sets a flag on the active run. The
/// in-flight Layer 0 command runs to completion (Layer 0 doesn't expose mid-flight
/// cancel for now), but no further steps are dispatched. If the descriptor
/// declares ``FleetRecipeDescriptor/cancelRecipe`` the runner dispatches that
/// recipe as cleanup before reporting the parent run as failed.
///
/// **Budgets:** ``FleetRecipeBody/overallBudgetSeconds`` is enforced as a hard
/// wall-clock cap on the run. Step-level command timeouts flow through the
/// catalogue's ``FleetCommandsCatalogue/defaultDispatchTimeoutSeconds`` and are
/// counted toward the recipe budget.
///
/// **Escalation:** see ``FleetRecipeEscalationEvent``. Unsupplied handlers fall
/// back to ``FleetRecipeDefaultEscalationHandler/abort``.
///
/// **Live wizard progress:** while ``executeBody`` runs for a vehicle, ``wizardProgressByVehicleID``
/// holds a ``FleetRecipeWizardProgressSnapshot`` for Vehicle Inspector chrome (Stage E). Cleared
/// when the top-level ``run`` exits.
///
/// **Wizard escalation:** ``vehicleInspectorWizardEscalationHandler(for:)`` publishes
/// ``wizardEscalationByVehicleID`` until the operator calls ``submitWizardEscalationVerb(vehicleID:verb:)``
/// or ``cancel(vehicleID:)`` (which auto-picks an allowed verb to unblock the handler).
@MainActor
final class FleetRecipeRunner: ObservableObject {

    // MARK: Singleton

    static let shared = FleetRecipeRunner()

    private init() {}

    // MARK: Wizard progress (Stage E UI)

    /// Live per-vehicle procedure progress for operator surfaces (Vehicle Inspector, future MCR).
    @Published private(set) var wizardProgressByVehicleID: [String: FleetRecipeWizardProgressSnapshot] = [:]

    /// When a run uses ``vehicleInspectorWizardEscalationHandler(for:)``, Layer 2 escalation is
    /// mirrored here until the operator picks a resumption verb (or cancel unblocks the await).
    @Published private(set) var wizardEscalationByVehicleID: [String: FleetRecipeWizardEscalationSnapshot] = [:]

    /// Mirrors the top-level ``activeRuns`` slot per vehicle so SwiftUI surfaces (Run row spinners,
    /// sheet chrome) refresh as soon as a recipe starts, without waiting on ``wizardProgressByVehicleID``.
    @Published private(set) var activeTopLevelRecipeNameByVehicleID: [String: FleetRecipeName] = [:]

    // MARK: Configuration

    /// Optional injection point for tests / Stage D plumbing — when non-`nil`,
    /// used instead of the live ``FleetCommandsCatalogue`` to dispatch commands.
    /// Production code leaves this `nil`; tests assign a deterministic stub.
    var commandInvokerOverride: FleetRecipeCommandInvoker?

    /// Default escalation handler used when ``run(...)`` is called without an
    /// explicit handler. Stage D will install the production prompt-router here
    /// at app start.
    var defaultEscalationHandler: FleetRecipeEscalationHandler = FleetRecipeDefaultEscalationHandler.abort

    /// Live-mission gate consulted at the top of ``run(...)``. `nil` means the
    /// runner does **not** enforce a live-mission gate at all (e.g. unit tests,
    /// or surfaces without a Mission Control store). Production callers install
    /// the gate once at app start.
    ///
    /// The gate is **only** consulted at the top of a top-level run (not at the
    /// boundary of `invokeRecipe` child expansions). The locked decision is that
    /// the parent recipe's risk tier is authoritative; if a child sub-recipe
    /// declares a stricter tier than its parent, that's an authoring mistake
    /// the catalogue catches at registration time (future work) rather than a
    /// runtime cross-check the runner performs.
    var liveMissionGate: FleetRecipeLiveMissionGate?

    // MARK: State

    /// Active runs keyed by `vehicleID`. One run per vehicle (locked decision).
    private var activeRuns: [String: ActiveRun] = [:]

    /// Continuations waiting on inline wizard escalation UI for a vehicle.
    private var pendingWizardEscalations: [String: (allowed: Set<FleetRecipeResumptionVerb>, continuation: CheckedContinuation<FleetRecipeResumptionVerb, Never>)] = [:]

    private let log = OSLog(subsystem: "guardian.fleet.recipesCatalogue", category: "runner")

    // MARK: Public surface

    /// Dispatch a registered recipe end-to-end. Returns the final outcome plus
    /// audit trace.
    ///
    /// Refuses to start (returns `.failed` immediately) when:
    /// - the recipe is not registered;
    /// - the descriptor has no body (registration-time hook for Stage C);
    /// - parameters fail the descriptor's schema;
    /// - the live-mission gate is installed, the vehicle is in a live mission,
    ///   `allowDuringLiveMission == false`, and the descriptor's risk tier is
    ///   `.groundOnly` or `.confirmInLiveMission`;
    /// - the vehicle already has an active run.
    ///
    /// `allowDuringLiveMission` mirrors the existing preflight override: callers
    /// who have already secured operator confirmation (Stage E wizard, MCR
    /// reserve-deploy / get-back-online flows) pass `true` to bypass the gate.
    /// `.safeInLiveMission` recipes ignore the gate regardless of this flag.
    func run(
        recipe name: FleetRecipeName,
        parameters: FleetRecipeParameters = .empty,
        vehicleID: String,
        source: String,
        fleetLink: FleetLinkService,
        allowDuringLiveMission: Bool = false,
        escalationHandler: FleetRecipeEscalationHandler? = nil
    ) async -> FleetRecipeOutcome {
        defer {
            clearWizardProgress(vehicleID: vehicleID)
            abandonWizardEscalationAwaitingResume(vehicleID: vehicleID)
        }

        let runID = FleetRecipeRunID()
        let trace = FleetRecipeAuditTrace(runID: runID, recipe: name, vehicleID: vehicleID)
        let handler = escalationHandler ?? defaultEscalationHandler

        // Resolve descriptor.
        guard let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name) else {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "No descriptor registered for \(name.rawValue).",
                trace: trace
            )
        }

        // Reject body-less descriptors at entry — Stage C will land bodies after
        // descriptors in a separate pass, and the runner must not silently
        // succeed on a recipe with nothing to do.
        guard let body = descriptor.body else {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Recipe \(name.rawValue) has no body. Register a FleetRecipeBody before running.",
                trace: trace
            )
        }

        // Validate parameters against the descriptor's schema before claiming
        // the vehicle slot.
        let validationFailures = FleetRecipeParameterValidator.validate(parameters, against: descriptor.parameters)
        if !validationFailures.isEmpty {
            let detail = validationFailures.map(\.loggable).joined(separator: "; ")
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Parameter validation failed: \(detail).",
                trace: trace
            )
        }

        // Live-mission gate. Consulted only at the top-level entry (not inside
        // `runInternal` for child expansions). Detail strings are stable so
        // wizard / MCR surfaces can detect the refusal type.
        if !allowDuringLiveMission,
           let gate = liveMissionGate,
           gate(vehicleID) {
            switch descriptor.riskTier {
            case .groundOnly:
                return .failed(
                    failingCommandPath: [],
                    lastResponse: nil,
                    detail: "Recipe \(name.rawValue) is groundOnly; vehicle \(vehicleID) is in a live mission. Pass allowDuringLiveMission=true to override.",
                    trace: trace
                )
            case .confirmInLiveMission:
                return .failed(
                    failingCommandPath: [],
                    lastResponse: nil,
                    detail: "Recipe \(name.rawValue) requires operator confirmation to run while vehicle \(vehicleID) is in a live mission. Pass allowDuringLiveMission=true after confirmation.",
                    trace: trace
                )
            case .safeInLiveMission:
                break
            }
        }

        // Per-vehicle conflict guard — refuse on conflict.
        if let existing = activeRuns[vehicleID] {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Vehicle \(vehicleID) already executing recipe \(existing.recipeName.rawValue) (run \(existing.runID)).",
                trace: trace
            )
        }

        let invoker = commandInvokerOverride ?? { @MainActor [weak fleetLink] commandName, commandParams, vid, src, timeout, invokingPluginID in
            guard let fleetLink else {
                return .error(
                    .dispatchFailed,
                    detail: "FleetLinkService released before dispatch.",
                    elapsed: nil
                )
            }
            return await FleetCommandsCatalogue.shared.invoke(
                commandName,
                parameters: commandParams,
                vehicleID: vid,
                source: src,
                fleetLink: fleetLink,
                timeout: timeout,
                invokingPluginID: invokingPluginID
            )
        }

        let active = ActiveRun(
            runID: runID,
            recipeName: name,
            vehicleID: vehicleID
        )
        installActiveRunSlot(vehicleID: vehicleID, run: active, topLevelRecipe: name)
        defer { removeActiveRunSlot(vehicleID: vehicleID) }

        os_log(
            .info,
            log: log,
            "Recipe %{public}@ starting (run %{public}@, vehicle %{public}@).",
            name.rawValue,
            String(describing: runID),
            vehicleID
        )

        // Prime Vehicle Inspector chrome before the first awaited dispatch so fast recipes
        // still show stable progress (and Run rows can observe ``activeTopLevelRecipeName``).
        publishWizardRunStarting(
            vehicleID: vehicleID,
            activeRun: active,
            descriptor: descriptor,
            body: body
        )
        await Task.yield()

        let outcome = await executeBody(
            body,
            descriptor: descriptor,
            parameters: parameters,
            vehicleID: vehicleID,
            source: source,
            invoker: invoker,
            escalationHandler: handler,
            active: active,
            trace: trace
        )

        // Cleanup recipe on cancel. Cancel-during-cleanup is a no-op (the
        // cleanup runs to completion or its own budget).
        if active.isCancelled, let cleanupName = descriptor.cancelRecipe {
            os_log(
                .info,
                log: log,
                "Recipe %{public}@ cancelled; dispatching cleanup %{public}@.",
                name.rawValue,
                cleanupName.rawValue
            )
            _ = await runInternal(
                recipe: cleanupName,
                parameters: .empty,
                vehicleID: vehicleID,
                source: "\(source)+cleanup",
                invoker: invoker,
                escalationHandler: handler,
                bypassConflictGate: true
            )
        }

        os_log(
            .info,
            log: log,
            "Recipe %{public}@ finished (run %{public}@): %{public}@",
            name.rawValue,
            String(describing: runID),
            outcome.loggable
        )

        return outcome
    }

    /// Cancel the active run on `vehicleID`, if any. Sets a flag observed by the
    /// runner loop at the next step boundary; the in-flight command (if any)
    /// runs to completion.
    @discardableResult
    func cancel(vehicleID: String) -> Bool {
        guard let active = activeRuns[vehicleID] else { return false }
        active.markCancelled()
        unblockWizardEscalationForCancelledRun(vehicleID: vehicleID)
        os_log(
            .info,
            log: log,
            "Cancel requested for run %{public}@ on vehicle %{public}@.",
            String(describing: active.runID),
            vehicleID
        )
        return true
    }

    /// Cancels the active run whose **top-level** id matches `runID`, if any.
    ///
    /// Prefer this from wizard chrome that carries ``FleetRecipeWizardProgressSnapshot/runID`` so
    /// cancel targets the operator-visible run even when a nested ``invokeRecipe`` is executing.
    /// Resolves to the same slot as ``cancel(vehicleID:)`` when `runID` matches that vehicle’s
    /// active top-level run.
    @discardableResult
    func cancel(runID: FleetRecipeRunID) -> Bool {
        for (vehicleID, active) in activeRuns where active.runID == runID {
            return cancel(vehicleID: vehicleID)
        }
        return false
    }

    /// Escalation handler that surfaces ``FleetRecipeEscalationEvent`` on ``wizardEscalationByVehicleID``
    /// until ``submitWizardEscalationVerb(vehicleID:verb:)`` returns the verb to the runner.
    ///
    /// - Precondition: the event's ``FleetRecipeEscalationEvent/vehicleID`` matches `vehicleID`
    ///   (defensive abort if not).
    func vehicleInspectorWizardEscalationHandler(for vehicleID: String) -> FleetRecipeEscalationHandler {
        { event in
            guard event.vehicleID == vehicleID else {
                return .abort
            }
            let snapshot = FleetRecipeWizardEscalationSnapshot.from(event: event)
            var next = self.wizardEscalationByVehicleID
            next[vehicleID] = snapshot
            self.wizardEscalationByVehicleID = next

            let verb = await withCheckedContinuation { (continuation: CheckedContinuation<FleetRecipeResumptionVerb, Never>) in
                self.pendingWizardEscalations[vehicleID] = (Set(event.allowedVerbs), continuation)
            }

            var cleared = self.wizardEscalationByVehicleID
            cleared.removeValue(forKey: vehicleID)
            self.wizardEscalationByVehicleID = cleared
            self.pendingWizardEscalations.removeValue(forKey: vehicleID)
            return verb
        }
    }

    /// Resume a wizard-blocked escalation with an operator-chosen verb. Returns `false` when no
    /// escalation is pending or `verb` is not in the event's ``FleetRecipeEscalationEvent/allowedVerbs``.
    @discardableResult
    func submitWizardEscalationVerb(vehicleID: String, verb: FleetRecipeResumptionVerb) -> Bool {
        guard let pending = pendingWizardEscalations.removeValue(forKey: vehicleID) else { return false }
        guard pending.allowed.contains(verb) else {
            pendingWizardEscalations[vehicleID] = pending
            return false
        }
        var next = wizardEscalationByVehicleID
        next.removeValue(forKey: vehicleID)
        wizardEscalationByVehicleID = next
        pending.continuation.resume(returning: verb)
        return true
    }

    /// Whether `vehicleID` currently has an active recipe run.
    func hasActiveRun(forVehicleID vehicleID: String) -> Bool {
        activeTopLevelRecipeNameByVehicleID[vehicleID] != nil
    }

    /// Top-level recipe name currently executing for `vehicleID`, if any.
    ///
    /// Child recipes expanded from ``invokeRecipe`` do **not** register their own slot in
    /// ``activeRuns``; while a nested body runs, this still reports the **outer** recipe the
    /// operator started (Vehicle Inspector row / cancel semantics stay aligned).
    func activeTopLevelRecipeName(forVehicleID vehicleID: String) -> FleetRecipeName? {
        activeTopLevelRecipeNameByVehicleID[vehicleID]
    }

    // MARK: Body execution

    /// Internal recipe execution path. `invokeRecipe` steps re-enter here with
    /// `bypassConflictGate: true` so the child recipe doesn't trip the
    /// per-vehicle uniqueness guard owned by the parent.
    private func runInternal(
        recipe name: FleetRecipeName,
        parameters: FleetRecipeParameters,
        vehicleID: String,
        source: String,
        invoker: @escaping FleetRecipeCommandInvoker,
        escalationHandler: @escaping FleetRecipeEscalationHandler,
        bypassConflictGate: Bool
    ) async -> FleetRecipeOutcome {

        let runID = FleetRecipeRunID()
        let trace = FleetRecipeAuditTrace(runID: runID, recipe: name, vehicleID: vehicleID)

        guard let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name) else {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "No descriptor registered for \(name.rawValue).",
                trace: trace
            )
        }
        guard let body = descriptor.body else {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Recipe \(name.rawValue) has no body.",
                trace: trace
            )
        }
        let validationFailures = FleetRecipeParameterValidator.validate(parameters, against: descriptor.parameters)
        if !validationFailures.isEmpty {
            let detail = validationFailures.map(\.loggable).joined(separator: "; ")
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Parameter validation failed: \(detail).",
                trace: trace
            )
        }
        if !bypassConflictGate, activeRuns[vehicleID] != nil {
            return .failed(
                failingCommandPath: [],
                lastResponse: nil,
                detail: "Vehicle \(vehicleID) already executing a recipe.",
                trace: trace
            )
        }

        let active = ActiveRun(runID: runID, recipeName: name, vehicleID: vehicleID)
        if !bypassConflictGate {
            installActiveRunSlot(vehicleID: vehicleID, run: active, topLevelRecipe: name)
        }
        defer {
            if !bypassConflictGate {
                removeActiveRunSlot(vehicleID: vehicleID)
            }
        }

        return await executeBody(
            body,
            descriptor: descriptor,
            parameters: parameters,
            vehicleID: vehicleID,
            source: source,
            invoker: invoker,
            escalationHandler: escalationHandler,
            active: active,
            trace: trace
        )
    }

    /// Core step-machine loop. Returns the final outcome with attached trace.
    ///
    /// Loop invariant: `cursor` is always a valid step ID in `body.steps`.
    /// Parser-time validation guarantees `entryStepID` and every `.branch` target
    /// exist, so the lookup-failure branch should never fire — it exists only as
    /// a defence against a manually-constructed body that bypassed the parser.
    private func executeBody(
        _ body: FleetRecipeBody,
        descriptor: FleetRecipeDescriptor,
        parameters: FleetRecipeParameters,
        vehicleID: String,
        source: String,
        invoker: @escaping FleetRecipeCommandInvoker,
        escalationHandler: @escaping FleetRecipeEscalationHandler,
        active: ActiveRun,
        trace initialTrace: FleetRecipeAuditTrace
    ) async -> FleetRecipeOutcome {

        var trace = initialTrace
        var cursor = body.entryStepID
        var lastResponse: FleetCommandResponse?
        let started = Date()
        let budget = body.overallBudgetSeconds

        loop: while true {

            // Budget gate — checked before each dispatch so a runaway loop
            // (back-to-back `.retry` outcomes, deep branch cycles) cannot
            // exceed the recipe's wall-clock cap.
            if Date().timeIntervalSince(started) >= budget {
                return .failed(
                    failingCommandPath: [cursor],
                    lastResponse: lastResponse,
                    detail: "Recipe budget exceeded (\(Int(budget))s).",
                    trace: trace
                )
            }

            // Cancellation gate — checked before each dispatch. Mid-flight
            // commands run to completion; the next step is suppressed.
            if active.isCancelled {
                return .failed(
                    failingCommandPath: [cursor],
                    lastResponse: lastResponse,
                    detail: "cancelled",
                    trace: trace
                )
            }

            guard let step = body.step(withID: cursor) else {
                return .failed(
                    failingCommandPath: [cursor],
                    lastResponse: lastResponse,
                    detail: "Unknown step ID \(cursor.rawValue) (parser invariant violated).",
                    trace: trace
                )
            }

            publishWizardProgress(
                vehicleID: vehicleID,
                activeRun: active,
                descriptor: descriptor,
                body: body,
                trace: trace,
                step: step
            )
            // First dispatch of a run: let SwiftUI paint wizard chrome before a long Layer 0 await
            // monopolises the main actor continuation (Vehicle Inspector Run row + banner).
            if trace.entries.isEmpty {
                await Task.yield()
            }

            // Dispatch the step (with auto-retry per the step / descriptor policy).
            let dispatch = await dispatchStep(
                step,
                descriptor: descriptor,
                parameters: parameters,
                vehicleID: vehicleID,
                source: source,
                invoker: invoker,
                escalationHandler: escalationHandler,
                budgetRemaining: max(0, budget - Date().timeIntervalSince(started))
            )

            lastResponse = dispatch.response

            // Apply matchers — first match wins.
            let outcome = applyMatchers(step.matchers, against: dispatch.response)

            // Record the trace entry before reacting (so failures still log).
            let entry = FleetRecipeAuditEntry(
                stepID: step.id,
                kind: traceKind(for: step),
                attempt: dispatch.attempts,
                response: dispatch.response,
                controlOutcome: outcome
            )
            trace.append(entry)
            os_log(.debug, log: log, "%{public}@", entry.loggable)

            guard let outcome else {
                // No matcher fired — treat as implicit fail. Parser already
                // requires the matcher list to be non-empty, but does not
                // require a catch-all.
                return .failed(
                    failingCommandPath: [step.id],
                    lastResponse: dispatch.response,
                    detail: "No matcher fired for step \(step.id.rawValue) (response: \(dispatch.response.outcome)).",
                    trace: trace
                )
            }

            switch outcome {

            case .continueToNextStep:
                guard let next = nextStepID(after: step.id, in: body) else {
                    return .succeeded(
                        detail: "Recipe completed (\(step.id.rawValue)).",
                        payload: dispatch.response.payload,
                        trace: trace
                    )
                }
                cursor = next

            case .branch(let target):
                guard body.step(withID: target) != nil else {
                    return .failed(
                        failingCommandPath: [step.id],
                        lastResponse: dispatch.response,
                        detail: "Branch target \(target.rawValue) does not exist (parser invariant violated).",
                        trace: trace
                    )
                }
                cursor = target

            case .retry:
                // Re-invoke this step from scratch. Auto-retries inside the
                // dispatch consume the retry policy; an explicit `.retry`
                // control outcome is **author-driven** and is bounded only by
                // the recipe's overall budget. Keeps the matcher vocabulary
                // expressive without needing a separate "explicit-retry"
                // counter on every step.
                continue loop

            case .succeed:
                return .succeeded(
                    detail: "Recipe completed by explicit succeed at \(step.id.rawValue).",
                    payload: dispatch.response.payload,
                    trace: trace
                )

            case .fail(let detail):
                return .failed(
                    failingCommandPath: [step.id],
                    lastResponse: dispatch.response,
                    detail: detail ?? "Recipe failed at \(step.id.rawValue).",
                    trace: trace
                )

            case .escalate(let reason, let allowedVerbs):
                let event = FleetRecipeEscalationEvent(
                    runID: wizardSnapshotRunID(vehicleID: vehicleID, activeRun: active),
                    recipe: descriptor.name,
                    vehicleID: vehicleID,
                    stepID: step.id,
                    reason: reason,
                    allowedVerbs: allowedVerbs,
                    lastResponse: dispatch.response
                )
                let verb = await escalationHandler(event)
                if !allowedVerbs.contains(verb) {
                    return .failed(
                        failingCommandPath: [step.id],
                        lastResponse: dispatch.response,
                        detail: "Escalation handler returned disallowed verb \(verb.rawValue) (allowed: \(allowedVerbs.map(\.rawValue).joined(separator: ","))).",
                        trace: trace
                    )
                }
                switch verb {
                case .acknowledge, .skip:
                    guard let next = nextStepID(after: step.id, in: body) else {
                        return .succeeded(
                            detail: "Recipe completed via escalation \(verb.rawValue) at \(step.id.rawValue).",
                            payload: dispatch.response.payload,
                            trace: trace
                        )
                    }
                    cursor = next
                case .retry:
                    continue loop
                case .abort:
                    return .failed(
                        failingCommandPath: [step.id],
                        lastResponse: dispatch.response,
                        detail: "Operator aborted at escalation (\(step.id.rawValue)).",
                        trace: trace
                    )
                }
            }
        }
    }

    // MARK: Step dispatch

    private struct StepDispatchResult {
        let response: FleetCommandResponse
        let attempts: Int
    }

    /// Dispatch a single step (with auto-retry per the resolved policy) and
    /// return the final response plus the number of attempts spent.
    private func dispatchStep(
        _ step: FleetRecipeStep,
        descriptor: FleetRecipeDescriptor,
        parameters: FleetRecipeParameters,
        vehicleID: String,
        source: String,
        invoker: @escaping FleetRecipeCommandInvoker,
        escalationHandler: @escaping FleetRecipeEscalationHandler,
        budgetRemaining: TimeInterval
    ) async -> StepDispatchResult {

        switch step {
        case .invokeCommand(_, let command, let stepParams, let stepRetry, _):
            let policy = stepRetry ?? descriptor.defaultRetryPolicy
            let stepTimeout = min(
                FleetCommandsCatalogue.defaultDispatchTimeoutSeconds,
                max(0.1, budgetRemaining)
            )
            var attempts = 0
            var response = FleetCommandResponse.error(
                .dispatchFailed,
                detail: "Dispatch loop did not run.",
                elapsed: 0
            )

            let resolvedStepParams: FleetRecipeParameters
            switch resolveStepParameters(stepParams, using: parameters) {
            case .resolved(let resolved):
                resolvedStepParams = resolved
            case .unresolvable(let detail):
                return StepDispatchResult(
                    response: .error(.dispatchFailed, detail: detail, elapsed: 0),
                    attempts: 0
                )
            }

            let commandParams = FleetCommandParameters(
                values: resolvedStepParams.values.mapValues { $0.asCommandParameterValue }
            )

            while attempts <= policy.maxAttempts {
                attempts += 1
                response = await invoker(command, commandParams, vehicleID, source, stepTimeout, descriptor.pluginID)
                if !policy.shouldRetry(response) { break }
                if attempts > policy.maxAttempts { break }
                if policy.delaySeconds > 0 {
                    let nanos = UInt64(policy.delaySeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                }
            }
            return StepDispatchResult(response: response, attempts: attempts)

        case .invokeRecipe(_, let recipeName, let stepParams, _):
            let resolvedStepParams: FleetRecipeParameters
            switch resolveStepParameters(stepParams, using: parameters) {
            case .resolved(let resolved):
                resolvedStepParams = resolved
            case .unresolvable(let detail):
                return StepDispatchResult(
                    response: .error(.dispatchFailed, detail: detail, elapsed: 0),
                    attempts: 0
                )
            }
            if let pluginID = descriptor.pluginID {
                guard let manifest = GuardianPluginRegistry.shared.manifest(for: pluginID) else {
                    return StepDispatchResult(
                        response: .error(
                            .dispatchFailed,
                            detail: "No GuardianPluginManifest for plugin \(pluginID.rawValue).",
                            elapsed: 0
                        ),
                        attempts: 0
                    )
                }
                guard manifest.allowsInvoking(recipeRaw: recipeName.rawValue) else {
                    return StepDispatchResult(
                        response: .error(
                            .dispatchFailed,
                            detail: "Recipe \(recipeName.rawValue) is outside plugin \(pluginID.rawValue) invokedRecipeNamespaces claims.",
                            elapsed: 0
                        ),
                        attempts: 0
                    )
                }
            }
            let childOutcome = await runInternal(
                recipe: recipeName,
                parameters: resolvedStepParams,
                vehicleID: vehicleID,
                source: source,
                invoker: invoker,
                escalationHandler: escalationHandler,
                bypassConflictGate: true
            )
            let synthetic = synthesiseResponse(forChildOutcome: childOutcome, child: recipeName)
            return StepDispatchResult(response: synthetic, attempts: 1)
        }
    }

    /// Resolve step-local `reference(name:)` values against the recipe run's
    /// caller-supplied parameters. Literal step values pass through unchanged.
    /// Parser validation guarantees references point at declared parameters for
    /// registered bodies, but the runner still handles misses defensively so
    /// manually-constructed test/plugin bodies fail cleanly instead of trapping.
    private func resolveStepParameters(
        _ stepParameters: FleetRecipeParameters,
        using runParameters: FleetRecipeParameters
    ) -> ParameterResolution {
        var resolved: [String: FleetRecipeParameterValue] = [:]
        for (key, value) in stepParameters.values {
            switch value {
            case .reference(let name):
                guard let supplied = runParameters.value(named: name) else {
                    return .unresolvable("Step parameter '\(key)' references missing recipe parameter '\(name)'.")
                }
                if case .reference = supplied {
                    return .unresolvable("Step parameter '\(key)' references unresolved recipe parameter '\(name)'.")
                }
                resolved[key] = supplied
            default:
                resolved[key] = value
            }
        }
        return .resolved(FleetRecipeParameters(values: resolved))
    }

    /// Internal result of `resolveStepParameters`. A bespoke enum avoids the
    /// `Result<_, String>` constraint that the failure type must conform to
    /// `Error`; the resolver's failure is a flat detail string we surface as
    /// `.dispatchFailed`, not a propagating error.
    private enum ParameterResolution {
        case resolved(FleetRecipeParameters)
        case unresolvable(String)
    }

    /// Project a child recipe's binary outcome down to a ``FleetCommandResponse``
    /// the parent's matchers can branch on. `.succeeded` → success; `.failed` →
    /// `error.unknown` with attribution in `detail`. Recipe authors who need
    /// to match on a child's failing kind should surface it through the child's
    /// own matchers; v1 keeps the bridge intentionally coarse.
    private func synthesiseResponse(
        forChildOutcome outcome: FleetRecipeOutcome,
        child: FleetRecipeName
    ) -> FleetCommandResponse {
        switch outcome {
        case .succeeded(let detail, let payload, _):
            return .success(
                detail: "Child recipe \(child.rawValue) succeeded\(detail.map { " (\($0))" } ?? "").",
                payload: payload,
                elapsed: nil
            )
        case .failed(let path, let lastResponse, let detail, _):
            let pathPart = path.map(\.rawValue).joined(separator: " -> ")
            return .error(
                .unknown,
                detail: "Child recipe \(child.rawValue) failed at [\(pathPart)]: \(detail ?? "no detail"); last=\(String(describing: lastResponse?.outcome)).",
                payload: lastResponse?.payload ?? .empty,
                elapsed: nil
            )
        }
    }

    // MARK: Helpers

    private func applyMatchers(
        _ matchers: [FleetRecipeStepMatcher],
        against response: FleetCommandResponse
    ) -> FleetRecipeControlOutcome? {
        for matcher in matchers where matcher.when.matches(response) {
            return matcher.then
        }
        return nil
    }

    private func nextStepID(after id: FleetRecipeStepID, in body: FleetRecipeBody) -> FleetRecipeStepID? {
        guard let idx = body.index(ofStepWithID: id) else { return nil }
        let next = idx + 1
        guard next < body.steps.count else { return nil }
        return body.steps[next].id
    }

    private func traceKind(for step: FleetRecipeStep) -> FleetRecipeAuditEntry.Kind {
        switch step {
        case .invokeCommand(_, let command, _, _, _): return .command(command)
        case .invokeRecipe(_, let recipe, _, _): return .recipe(recipe)
        }
    }

    // MARK: Wizard progress publishing

    /// Wizard / escalation chrome always correlates to the **top-level** run (``activeRuns`` slot).
    /// Nested ``invokeRecipe`` bodies use their own ``ActiveRun`` identity internally; snapshots and
    /// ``FleetRecipeEscalationEvent`` still carry the outer run id so ``cancel(runID:)`` matches the
    /// Vehicle Inspector banner.
    private func wizardSnapshotRunID(vehicleID: String, activeRun: ActiveRun) -> FleetRecipeRunID {
        if let slot = activeRuns[vehicleID] {
            return slot.runID
        }
        return activeRun.runID
    }

    private func publishWizardRunStarting(
        vehicleID: String,
        activeRun: ActiveRun,
        descriptor: FleetRecipeDescriptor,
        body: FleetRecipeBody
    ) {
        guard let entryStep = body.step(withID: body.entryStepID) else { return }
        let authoredFloor = max(body.steps.count, 1)
        var next = wizardProgressByVehicleID
        next[vehicleID] = FleetRecipeWizardProgressSnapshot(
            runID: wizardSnapshotRunID(vehicleID: vehicleID, activeRun: activeRun),
            recipeHumanTitle: descriptor.humanLabel,
            stepOrdinal: 1,
            stepTotal: authoredFloor,
            currentStepID: entryStep.id,
            activityLine: "Starting procedure…"
        )
        wizardProgressByVehicleID = next
    }

    private func publishWizardProgress(
        vehicleID: String,
        activeRun: ActiveRun,
        descriptor: FleetRecipeDescriptor,
        body: FleetRecipeBody,
        trace: FleetRecipeAuditTrace,
        step: FleetRecipeStep
    ) {
        let dispatchOrdinal = trace.entries.count + 1
        let authoredFloor = max(body.steps.count, 1)
        let displayTotal = max(authoredFloor, dispatchOrdinal)
        var next = wizardProgressByVehicleID
        next[vehicleID] = FleetRecipeWizardProgressSnapshot(
            runID: wizardSnapshotRunID(vehicleID: vehicleID, activeRun: activeRun),
            recipeHumanTitle: descriptor.humanLabel,
            stepOrdinal: dispatchOrdinal,
            stepTotal: displayTotal,
            currentStepID: step.id,
            activityLine: wizardActivityLine(for: step)
        )
        wizardProgressByVehicleID = next
    }

    private func clearWizardProgress(vehicleID: String) {
        var next = wizardProgressByVehicleID
        next.removeValue(forKey: vehicleID)
        wizardProgressByVehicleID = next
    }

    /// Picks a verb that unblocks an escalation await after **Cancel** or run teardown. Prefers
    /// ``abort`` so the recipe tends to end immediately when the operator asked to stop; otherwise
    /// falls back through lighter-weight verbs so the handler always resumes.
    private func bestUnblockVerb(from allowed: Set<FleetRecipeResumptionVerb>) -> FleetRecipeResumptionVerb {
        if allowed.contains(.abort) { return .abort }
        if allowed.contains(.skip) { return .skip }
        if allowed.contains(.acknowledge) { return .acknowledge }
        if allowed.contains(.retry) { return .retry }
        return .abort
    }

    private func unblockWizardEscalationForCancelledRun(vehicleID: String) {
        guard let pending = pendingWizardEscalations.removeValue(forKey: vehicleID) else { return }
        var next = wizardEscalationByVehicleID
        next.removeValue(forKey: vehicleID)
        wizardEscalationByVehicleID = next
        let verb = bestUnblockVerb(from: pending.allowed)
        pending.continuation.resume(returning: verb)
    }

    /// If a wizard escalation continuation is still pending when the top-level ``run`` exits,
    /// resume it so the handler never leaks an await (e.g. unexpected failure paths).
    private func abandonWizardEscalationAwaitingResume(vehicleID: String) {
        guard let pending = pendingWizardEscalations.removeValue(forKey: vehicleID) else {
            var escOnly = wizardEscalationByVehicleID
            if escOnly.removeValue(forKey: vehicleID) != nil {
                wizardEscalationByVehicleID = escOnly
            }
            return
        }
        var esc = wizardEscalationByVehicleID
        esc.removeValue(forKey: vehicleID)
        wizardEscalationByVehicleID = esc
        let verb = bestUnblockVerb(from: pending.allowed)
        pending.continuation.resume(returning: verb)
    }

    private func installActiveRunSlot(vehicleID: String, run: ActiveRun, topLevelRecipe: FleetRecipeName) {
        activeRuns[vehicleID] = run
        var next = activeTopLevelRecipeNameByVehicleID
        next[vehicleID] = topLevelRecipe
        activeTopLevelRecipeNameByVehicleID = next
    }

    private func removeActiveRunSlot(vehicleID: String) {
        activeRuns.removeValue(forKey: vehicleID)
        var next = activeTopLevelRecipeNameByVehicleID
        if next.removeValue(forKey: vehicleID) != nil {
            activeTopLevelRecipeNameByVehicleID = next
        }
    }

    private func wizardActivityLine(for step: FleetRecipeStep) -> String {
        switch step {
        case .invokeCommand(_, let command, _, _, _):
            return command.rawValue
        case .invokeRecipe(_, let recipe, _, _):
            if let child = FleetRecipesCatalogue.shared.descriptor(for: recipe) {
                return "Nested procedure: \(child.humanLabel)"
            }
            return "Nested procedure: \(recipe.rawValue)"
        }
    }

    // MARK: Active-run handle

    /// Mutable per-run state owned by the runner. Reference type so the loop
    /// and the cancel API observe the same cancellation flag without round-tripping
    /// through `activeRuns`.
    private final class ActiveRun {
        let runID: FleetRecipeRunID
        let recipeName: FleetRecipeName
        let vehicleID: String
        private(set) var isCancelled: Bool = false

        init(runID: FleetRecipeRunID, recipeName: FleetRecipeName, vehicleID: String) {
            self.runID = runID
            self.recipeName = recipeName
            self.vehicleID = vehicleID
        }

        func markCancelled() {
            isCancelled = true
        }
    }

    // MARK: Test-only reset

    /// Clears any lingering active-run state. Used by unit tests between scenarios
    /// so a refusing-on-conflict assertion in one test can't be polluted by a
    /// previous test's leaked run.
    func _testOnlyResetActiveRuns() {
        let stuckVehicles = Array(pendingWizardEscalations.keys)
        for vid in stuckVehicles {
            abandonWizardEscalationAwaitingResume(vehicleID: vid)
        }
        activeRuns.removeAll()
        activeTopLevelRecipeNameByVehicleID = [:]
        wizardProgressByVehicleID = [:]
        wizardEscalationByVehicleID = [:]
        pendingWizardEscalations.removeAll()
        commandInvokerOverride = nil
        defaultEscalationHandler = FleetRecipeDefaultEscalationHandler.abort
        liveMissionGate = nil
    }
}
