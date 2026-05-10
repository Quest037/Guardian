import Foundation

/// Fallback converter for vehicles whose autopilot stack is not yet identified
/// (`FleetAutopilotStack.unknown`). Telemetry reads are still served from the hub
/// snapshot; everything else returns `.notImplemented` with a clear detail so recipes
/// can either escalate or branch on the kind.
///
/// Registering this explicitly keeps ``FleetCommandsCatalogue/invoke(...)`` from ever
/// having to special-case a missing converter — the resolution always succeeds for the
/// three known stacks.
struct FleetCommandStackConverterUnknown: FleetCommandStackConverter {

    let stack: FleetAutopilotStack = .unknown

    func translate(
        commandName: FleetCommandName,
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation {

        // Telemetry reads work regardless of stack — the hub snapshot is normalised.
        if let immediate = FleetCommandStackConverterShared.translateGetTelemetry(
            commandName: commandName,
            hub: context.hubTelemetry
        ) {
            return immediate
        }
        return .notImplemented(detail: "Autopilot stack is unknown — no translation available for \(commandName.rawValue) until MAVLink stack identification completes.")
    }

    func normaliseOutcome(
        _ outcome: FleetCommandAsyncOutcome,
        commandName: FleetCommandName,
        elapsed: TimeInterval
    ) -> FleetCommandResponse {
        FleetCommandStackConverterShared.normaliseOutcome(
            outcome,
            commandName: commandName,
            elapsed: elapsed
        )
    }
}
