import XCTest
@testable import GuardianCore

/// Stage B0 stack-converter coverage. Walks the registered descriptors and confirms
/// each known autopilot stack returns a defined ``FleetCommandStackTranslation`` for
/// every one — i.e. there is no `fatalError` / silent crash hole in the switches. Each
/// command is allowed to resolve to either a real translation or `.notImplemented`, but
/// it must not trap.
@MainActor
final class FleetCommandStackConverterCoverageTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    /// A "best effort" parameter bundle that satisfies every required declaration on a
    /// descriptor with a stub value. Lets the coverage test reach the converter even for
    /// descriptors that gate on required parameters.
    private func stubParameters(forDescriptor descriptor: FleetCommandDescriptor) -> FleetCommandParameters {
        var values: [String: FleetCommandParameterValue] = [:]
        for declaration in descriptor.parameters where declaration.isRequired {
            switch declaration.type {
            case .bool:
                values[declaration.name] = .bool(false)
            case .integer:
                values[declaration.name] = .integer(1)
            case .double:
                values[declaration.name] = .double(1.0)
            case .string:
                if let allowed = declaration.allowedStringValues, let pick = allowed.first {
                    values[declaration.name] = .string(pick)
                } else {
                    values[declaration.name] = .string("stub")
                }
            case .stringList:
                values[declaration.name] = .stringList(["stub"])
            }
        }
        return FleetCommandParameters(values: values)
    }

    private func telemetryWithKnownPosition() -> FleetHubVehicleTelemetry {
        var telemetry = FleetHubVehicleTelemetry.empty
        telemetry.latitudeDeg = 51.5074
        telemetry.longitudeDeg = -0.1278
        telemetry.absoluteAltM = 35.0
        telemetry.relativeAltM = 5.0
        telemetry.altitudeAmslM = 35.0
        telemetry.headingDeg = 90.0
        return telemetry
    }

    func test_arduPilotConverter_returnsADefinedTranslationForEveryRegisteredCommand() {
        let converter = FleetCommandStackConverterArduPilot()
        let context = FleetCommandStackConverterContext(
            vehicleID: "TEST-SYS-1",
            vehicleType: .uavCopter,
            hubTelemetry: telemetryWithKnownPosition()
        )

        for (name, descriptor) in FleetCommandsCatalogue.shared.descriptors {
            let parameters = stubParameters(forDescriptor: descriptor)
            let translation = converter.translate(
                commandName: name,
                parameters: parameters,
                context: context
            )
            // Mere existence asserts the converter handled the literal — any non-handled
            // descriptor would either trap or fall through to default. Pin the shape.
            switch translation {
            case .vehicleCommands, .immediate, .notImplemented:
                break
            }
        }
    }

    func test_pX4Converter_returnsADefinedTranslationForEveryRegisteredCommand() {
        let converter = FleetCommandStackConverterPX4()
        let context = FleetCommandStackConverterContext(
            vehicleID: "TEST-SYS-2",
            vehicleType: .uavCopter,
            hubTelemetry: telemetryWithKnownPosition()
        )

        for (name, descriptor) in FleetCommandsCatalogue.shared.descriptors {
            let parameters = stubParameters(forDescriptor: descriptor)
            let translation = converter.translate(
                commandName: name,
                parameters: parameters,
                context: context
            )
            switch translation {
            case .vehicleCommands, .immediate, .notImplemented:
                break
            }
        }
    }

    func test_unknownStackConverter_neverReturnsVehicleCommands() {
        let converter = FleetCommandStackConverterUnknown()
        let context = FleetCommandStackConverterContext(
            vehicleID: "TEST-SYS-3",
            vehicleType: .unknown,
            hubTelemetry: telemetryWithKnownPosition()
        )

        for (name, descriptor) in FleetCommandsCatalogue.shared.descriptors {
            let parameters = stubParameters(forDescriptor: descriptor)
            let translation = converter.translate(
                commandName: name,
                parameters: parameters,
                context: context
            )
            if case .vehicleCommands = translation {
                XCTFail("Unknown stack converter must not emit vehicleCommands for \(name.rawValue) — there is no autopilot to dispatch to.")
            }
        }
    }
}
