import Combine
import Foundation
import os

// MARK: - Outcome continuation gate

/// Single-fire gate around a `CheckedContinuation<FleetCommandAsyncOutcome, Never>`.
/// Mirrors the timeout-safe continuation pattern used by Layer 0 dispatch so the
/// catalogue can race a dispatch callback against a timeout without ever resuming the
/// continuation twice (which would trap).
private final class FleetCommandOutcomeContinuationGate: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    func resume(
        _ continuation: CheckedContinuation<FleetCommandAsyncOutcome, Never>,
        returning outcome: FleetCommandAsyncOutcome
    ) {
        lock.lock()
        let shouldFire = !hasResumed
        if shouldFire { hasResumed = true }
        lock.unlock()
        guard shouldFire else { return }
        continuation.resume(returning: outcome)
    }
}

// MARK: - Catalogue

/// **Layer 0 — universal command registry.**
///
/// Holds the ``FleetCommandDescriptor`` for every registered command in the universal
/// `command.*` namespace, plus a stack converter per ``FleetAutopilotStack``. Provides
/// the typed `invoke` pipeline that Layer 1 recipes (and any direct callers) consume.
///
/// **Lifecycle:** singleton, populated once at app start by
/// ``FleetCommandsCatalogueBootstrap/ensureRegistered()`` (idempotent). Subsystems
/// register their commands inside the bootstrap; plugins will register through their
/// own bootstrap once Stage F manifest namespace claims land.
///
/// **Thread isolation:** `@MainActor`. Registrations and lookups are main-thread; the
/// `invoke` pipeline hops to background work via async/await + `FleetLinkService`'s
/// existing dispatch machinery.
@MainActor
final class FleetCommandsCatalogue: ObservableObject {

    // MARK: Singleton

    static let shared = FleetCommandsCatalogue()
    private init() {}

    // MARK: Storage

    /// Registered descriptors, keyed by name.
    @Published private(set) var descriptors: [FleetCommandName: FleetCommandDescriptor] = [:]

    /// Registered stack converters, keyed by stack.
    private var stackConverters: [FleetAutopilotStack: any FleetCommandStackConverter] = [:]

    private let log = OSLog(subsystem: "guardian.fleet.commandsCatalogue", category: "registry")

    // MARK: Registration

    /// Idempotent registration. Last write wins per name.
    ///
    /// **Plugin publish claims (Stage F):** when ``FleetCommandDescriptor/pluginID`` is
    /// non-`nil`, the name must fall under one of that plugin’s
    /// ``GuardianPluginManifest/publishedCommandNamespaces`` entries in
    /// ``GuardianPluginRegistry`` (exact prefix or `prefix.` + suffix). Missing manifest
    /// or an out-of-claim name is rejected.
    ///
    /// **Composition rule (v1):** if `descriptor.containsCommands` is non-empty, every
    /// referenced child must already be registered AND the child must itself have an
    /// empty `containsCommands` list. The registry rejects deeper nesting at this
    /// boundary so we never have to detect cycles or unbounded depth at run time.
    @discardableResult
    func register(_ descriptor: FleetCommandDescriptor) -> Bool {
        guard FleetCommandName.isValidRawValue(descriptor.name.rawValue) else {
            os_log(
                .fault,
                log: log,
                "Refusing to register descriptor with invalid name: %{public}@",
                descriptor.name.rawValue
            )
            return false
        }
        if let pluginID = descriptor.pluginID {
            guard let manifest = GuardianPluginRegistry.shared.manifest(for: pluginID) else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: no GuardianPluginManifest for plugin %{public}@.",
                    descriptor.name.rawValue,
                    pluginID.rawValue
                )
                return false
            }
            guard manifest.allowsPublishing(commandRaw: descriptor.name.rawValue) else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: name is outside plugin %{public}@ publishedCommandNamespaces claims.",
                    descriptor.name.rawValue,
                    pluginID.rawValue
                )
                return false
            }
        }
        for childName in descriptor.containsCommands {
            guard let child = descriptors[childName] else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: contained child %{public}@ not yet registered.",
                    descriptor.name.rawValue,
                    childName.rawValue
                )
                return false
            }
            guard child.containsCommands.isEmpty else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: composition depth limit (1) violated by child %{public}@.",
                    descriptor.name.rawValue,
                    childName.rawValue
                )
                return false
            }
        }
        descriptors[descriptor.name] = descriptor
        return true
    }

    /// Idempotent stack-converter registration. Last write wins per stack.
    func registerStackConverter(_ converter: any FleetCommandStackConverter) {
        stackConverters[converter.stack] = converter
    }

    // MARK: Lookup

    func descriptor(for name: FleetCommandName) -> FleetCommandDescriptor? {
        descriptors[name]
    }

    func descriptor(forRawValue raw: String) -> FleetCommandDescriptor? {
        guard let name = try? FleetCommandName(validating: raw) else { return nil }
        return descriptors[name]
    }

    /// All descriptors whose addressing path begins with the given prefix. Useful for
    /// surfaces that want "every `command.fleet.vehicle.do.calibrate.*`" — they pass
    /// `["fleet", "vehicle", "do", "calibrate"]` (verb included) or
    /// `["fleet", "vehicle"]` (any verb).
    func descriptors(underPrefix prefix: [String]) -> [FleetCommandDescriptor] {
        descriptors.values.filter { $0.name.isUnderAddressingPrefix(prefix) || prefixIncludesVerb(prefix, name: $0.name) }
    }

    private func prefixIncludesVerb(_ prefix: [String], name: FleetCommandName) -> Bool {
        // Prefix includes the verb segment (e.g. `[fleet, vehicle, do, calibrate]`).
        let segments = name.rawValue.split(separator: ".").map(String.init).dropFirst()
        guard prefix.count <= segments.count else { return false }
        return Array(segments.prefix(prefix.count)) == prefix
    }

    func stackConverter(for stack: FleetAutopilotStack) -> (any FleetCommandStackConverter)? {
        stackConverters[stack]
    }

    // MARK: Invocation

    /// Configurable per-step timeout for raw `FleetVehicleCommand` dispatches. Layer 1
    /// recipes can apply tighter or looser budgets at the recipe level; this is a
    /// safety net so a single `invoke` call cannot hang forever.
    static let defaultDispatchTimeoutSeconds: TimeInterval = 30

    /// Execute a registered command end-to-end:
    ///
    /// 1. Resolve descriptor — fail with `.unknownCommand` if missing.
    /// 2. When `invokingPluginID` is set, enforce that manifest’s ``GuardianPluginManifest/invokedCommandNamespaces``
    ///    covers this command name — fail with `.dispatchFailed` if not.
    /// 3. Validate parameters against the descriptor's schema — fail with
    ///    `.dispatchFailed` (with full failure detail) on any mismatch.
    /// 4. Resolve vehicle model + autopilot stack — fail with `.noVehicle` /
    ///    `.notConnected` accordingly.
    /// 5. Resolve stack converter — fail with `.notImplemented` if absent.
    /// 6. Translate the command to a dispatch product. `.immediate` returns directly;
    ///    `.notImplemented` becomes `.error(.notImplemented)`; `.vehicleCommands` is
    ///    dispatched sequentially via `FleetLinkService`. First failure short-circuits.
    /// 7. Normalise the final outcome via the converter and return a typed response.
    ///
    /// **Composite descriptors:** if `descriptor.containsCommands` is non-empty, the
    /// catalogue invokes each child `invoke(...)` recursively (depth always = 1 because
    /// of the registration-time depth guard). First child failure short-circuits.
    ///
    /// **Plugin invoke claims (Stage F):** when `invokingPluginID` is non-`nil`, the
    /// resolved command name must fall under that plugin’s ``GuardianPluginManifest/invokedCommandNamespaces``
    /// in ``GuardianPluginRegistry`` (same prefix rule as publish claims). Core callers omit this.
    func invoke(
        _ name: FleetCommandName,
        parameters: FleetCommandParameters = .empty,
        vehicleID: String,
        source: String,
        fleetLink: FleetLinkService,
        timeout: TimeInterval = FleetCommandsCatalogue.defaultDispatchTimeoutSeconds,
        invokingPluginID: GuardianPluginID? = nil
    ) async -> FleetCommandResponse {

        let started = Date()

        // 1. Resolve descriptor.
        guard let descriptor = descriptors[name] else {
            return .error(
                .unknownCommand,
                detail: "No descriptor registered for \(name.rawValue).",
                elapsed: Date().timeIntervalSince(started)
            )
        }

        if let pluginID = invokingPluginID {
            guard let manifest = GuardianPluginRegistry.shared.manifest(for: pluginID) else {
                return .error(
                    .dispatchFailed,
                    detail: "No GuardianPluginManifest for plugin \(pluginID.rawValue).",
                    elapsed: Date().timeIntervalSince(started)
                )
            }
            guard manifest.allowsInvoking(commandRaw: name.rawValue) else {
                return .error(
                    .dispatchFailed,
                    detail: "Command \(name.rawValue) is outside plugin \(pluginID.rawValue) invokedCommandNamespaces claims.",
                    elapsed: Date().timeIntervalSince(started)
                )
            }
        }

        // 2. Validate parameters.
        let validationFailures = FleetCommandParameterValidator.validate(parameters, against: descriptor.parameters)
        if !validationFailures.isEmpty {
            let detail = validationFailures.map(\.loggable).joined(separator: "; ")
            return .error(
                .dispatchFailed,
                detail: "Parameter validation failed: \(detail).",
                elapsed: Date().timeIntervalSince(started)
            )
        }

        // 3. Composite descriptors: expand to child invocations (1 level deep).
        if descriptor.isComposite {
            return await invokeComposite(
                descriptor: descriptor,
                parameters: parameters,
                vehicleID: vehicleID,
                source: source,
                fleetLink: fleetLink,
                timeout: timeout,
                started: started,
                invokingPluginID: invokingPluginID
            )
        }

        // 4. Resolve vehicle + stack.
        guard let model = fleetLink.vehicleModel(forVehicleID: vehicleID) else {
            return .error(
                .noVehicle,
                detail: "No vehicle model for stream key \(vehicleID).",
                elapsed: Date().timeIntervalSince(started)
            )
        }
        guard model.collections.lifecycleStatus.stage == .live else {
            return .error(
                .notConnected,
                detail: "Vehicle stage is \(model.collections.lifecycleStatus.stage.rawValue).",
                elapsed: Date().timeIntervalSince(started)
            )
        }
        let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack ?? .unknown
        guard let converter = stackConverters[stack] else {
            return .error(
                .notImplemented,
                detail: "No stack converter registered for \(stack.displayName).",
                elapsed: Date().timeIntervalSince(started)
            )
        }

        // 5. Translate.
        let context = FleetCommandStackConverterContext(
            vehicleID: vehicleID,
            vehicleType: model.data.vehicleType,
            hubTelemetry: fleetLink.hubTelemetry(forVehicleID: vehicleID)
        )
        let translation = converter.translate(
            commandName: name,
            parameters: parameters,
            context: context
        )

        switch translation {
        case .immediate(let response):
            return response
        case .notImplemented(let detail):
            return .error(
                .notImplemented,
                detail: "\(stack.displayName): \(detail)",
                elapsed: Date().timeIntervalSince(started)
            )
        case .vehicleCommands(let commands):
            return await dispatchSequentially(
                commands: commands,
                commandName: name,
                converter: converter,
                vehicleID: vehicleID,
                source: source,
                fleetLink: fleetLink,
                timeout: timeout,
                started: started
            )
        }
    }

    // MARK: Composite expansion

    /// Sequentially invokes each child of a composite descriptor. First child failure
    /// short-circuits and is returned with detail attributed to the failing child.
    private func invokeComposite(
        descriptor: FleetCommandDescriptor,
        parameters: FleetCommandParameters,
        vehicleID: String,
        source: String,
        fleetLink: FleetLinkService,
        timeout: TimeInterval,
        started: Date,
        invokingPluginID: GuardianPluginID?
    ) async -> FleetCommandResponse {

        for childName in descriptor.containsCommands {
            // Forward the parent's validated parameters so composites like
            // `do.mission.upload.start` can pass `missionItemsJSON` through to upload/start;
            // children with no matching declarations ignore extras (e.g. `do.arm`).
            let childResponse = await invoke(
                childName,
                parameters: parameters,
                vehicleID: vehicleID,
                source: source,
                fleetLink: fleetLink,
                timeout: timeout,
                invokingPluginID: invokingPluginID
            )
            if !childResponse.isSuccess {
                return FleetCommandResponse(
                    outcome: childResponse.outcome,
                    detail: "Composite \(descriptor.name.rawValue) failed at \(childName.rawValue): \(childResponse.detail ?? "no detail")",
                    payload: childResponse.payload,
                    elapsed: Date().timeIntervalSince(started)
                )
            }
        }
        return .success(
            detail: "Composite \(descriptor.name.rawValue) completed.",
            payload: .empty,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    // MARK: Sequential dispatch

    /// Dispatch one or more `FleetVehicleCommand` cases sequentially. First failure
    /// short-circuits; the returned response is normalised by the stack converter.
    private func dispatchSequentially(
        commands: [FleetVehicleCommand],
        commandName: FleetCommandName,
        converter: any FleetCommandStackConverter,
        vehicleID: String,
        source: String,
        fleetLink: FleetLinkService,
        timeout: TimeInterval,
        started: Date
    ) async -> FleetCommandResponse {

        // Empty translation = no-op success. Stack converters that intend "not
        // implemented" should return `.notImplemented`, not an empty list.
        guard !commands.isEmpty else {
            return .success(
                detail: "No vehicle commands required for \(commandName.rawValue).",
                payload: .empty,
                elapsed: Date().timeIntervalSince(started)
            )
        }

        var lastOutcome: FleetCommandAsyncOutcome = .succeeded
        for command in commands {
            lastOutcome = await dispatchOne(
                command: command,
                vehicleID: vehicleID,
                source: source,
                fleetLink: fleetLink,
                timeout: timeout
            )
            if case .failed = lastOutcome { break }
        }
        return converter.normaliseOutcome(
            lastOutcome,
            commandName: commandName,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    /// Dispatch a single `FleetVehicleCommand` and await its outcome with a hard
    /// timeout. The timeout is racy-safe via ``FleetCommandOutcomeContinuationGate`` —
    /// whichever side resolves first wins; the other side becomes a no-op.
    private func dispatchOne(
        command: FleetVehicleCommand,
        vehicleID: String,
        source: String,
        fleetLink: FleetLinkService,
        timeout: TimeInterval
    ) async -> FleetCommandAsyncOutcome {

        await withCheckedContinuation { (continuation: CheckedContinuation<FleetCommandAsyncOutcome, Never>) in
            let gate = FleetCommandOutcomeContinuationGate()
            let timeoutNanos = UInt64(max(0.001, timeout) * 1_000_000_000)
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                } catch {
                    return
                }
                gate.resume(continuation, returning: .failed("Timed out after \(Int(timeout))s waiting for vehicle outcome."))
            }
            _ = fleetLink.executeVehicleCommand(
                vehicleID: vehicleID,
                command: command,
                source: source,
                category: .missionControl
            ) { outcome in
                timeoutTask.cancel()
                gate.resume(continuation, returning: outcome)
            }
        }
    }
}
