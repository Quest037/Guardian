import Foundation

// MARK: - Translation product

/// What a stack converter produces when asked to translate a registered command.
///
/// This is the contract surface between the catalogue's `invoke` pipeline and the
/// per-stack autopilot adapters. Each case directs the catalogue's dispatcher to a
/// different execution path.
enum FleetCommandStackTranslation {

    /// Dispatch this concrete sequence of `FleetVehicleCommand` cases through
    /// ``FleetLinkService/executeVehicleCommand(vehicleID:command:source:category:onCommandOutcome:)``.
    /// The catalogue runs them sequentially; first failure short-circuits the rest.
    case vehicleCommands([FleetVehicleCommand])

    /// The translation already produced an outcome (e.g. an immediate read from the
    /// hub telemetry cache for `command.get.*`). The catalogue returns this response
    /// directly without dispatching anything to the vehicle.
    case immediate(FleetCommandResponse)

    /// This stack does not implement the requested command. The catalogue normalises
    /// this to `.error(.notImplemented)` with `detail` populated for log clarity.
    case notImplemented(detail: String)
}

// MARK: - Translation context

/// Read-only slice of vehicle state passed into the converter when translating /
/// normalising. Keeps the protocol decoupled from `FleetLinkService` and easy to test
/// with synthetic vehicles.
struct FleetCommandStackConverterContext: Sendable {
    /// Stable vehicle stream key (same identifier used elsewhere in the Fleet system).
    let vehicleID: String
    /// Vehicle class, e.g. `.uavCopter`. May be `.unknown` until MAV_TYPE inference lands.
    let vehicleType: FleetVehicleType
    /// Latest hub telemetry snapshot. `nil` when no telemetry has arrived yet.
    let hubTelemetry: FleetHubVehicleTelemetry?
}

// MARK: - Stack converter protocol

/// Per-autopilot-stack adapter. Implementations live under
/// `Subsystems/CommandsCatalogue/Stacks/` and are registered into the catalogue at
/// ``FleetCommandsCatalogueBootstrap/ensureRegistered()`` time.
///
/// **Two responsibilities:**
///
/// 1. ``translate(commandName:parameters:context:)`` — produce a
///    ``FleetCommandStackTranslation`` for the given registered command. This is where
///    PX4 vs ArduPilot semantic divergence lives.
/// 2. ``normaliseOutcome(_:commandName:elapsed:)`` — convert the raw
///    ``FleetCommandAsyncOutcome`` from `FleetLinkService` into a typed
///    ``FleetCommandResponse``. This is where stack-specific failure-string parsing
///    lives.
///
/// Implementations should be pure / stateless so they remain safe to call from any
/// actor. They must not retain `FleetLinkService` or any other reference; the
/// catalogue passes context in via ``FleetCommandStackConverterContext`` for each call.
protocol FleetCommandStackConverter: Sendable {

    /// The autopilot stack this converter implements.
    var stack: FleetAutopilotStack { get }

    /// Translate a registered command name + parameters into a dispatch product.
    ///
    /// - Returns: ``FleetCommandStackTranslation/notImplemented(detail:)`` when this
    ///   stack has no implementation for the command. The catalogue surfaces this as
    ///   `.error(.notImplemented)`.
    func translate(
        commandName: FleetCommandName,
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation

    /// Normalise a raw outcome into the typed response taxonomy. Called by the
    /// catalogue after every `FleetVehicleCommand` it dispatches. The full
    /// ``FleetCommandName`` is provided so converters can adjust their classification
    /// per command (e.g. "already armed" is `.alreadyArmed` for `do.arm` but
    /// `.alreadyDisarmed` for `do.disarm`).
    func normaliseOutcome(
        _ outcome: FleetCommandAsyncOutcome,
        commandName: FleetCommandName,
        elapsed: TimeInterval
    ) -> FleetCommandResponse
}
