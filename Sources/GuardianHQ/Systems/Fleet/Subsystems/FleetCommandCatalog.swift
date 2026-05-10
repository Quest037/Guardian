import Foundation

// MARK: - JSON file shape

/// One command entry in ``FleetCommandCatalog.json``.
struct FleetCommandCatalogEntry: Codable, Equatable, Sendable {
    var label: String
    var description: String
    /// Keys are vehicle class codes (``FleetVehicleType/classCode``), e.g. `UAV-C`, `UGV-L`.
    var commands: [String: [FleetSemanticStepJSONObject]]
}

enum FleetCommandCatalogError: Error, Sendable {
    case missingBundledCatalog
    case decoding(underlying: any Error)
}

// MARK: - Catalog (load JSON → parse → convert per stack)

/// Loads fleet command definitions from JSON, parses semantic step arrays, and converts them to
/// stack-specific ``FleetVehicleCommand`` sequences via per-stack converter files.
final class FleetCommandCatalog: @unchecked Sendable {

    private let entries: [String: FleetCommandCatalogEntry]

    /// Decodes a catalog document: top-level keys are command names; values are ``FleetCommandCatalogEntry``.
    init(jsonData: Data) throws {
        do {
            entries = try JSONDecoder().decode([String: FleetCommandCatalogEntry].self, from: jsonData)
        } catch {
            throw FleetCommandCatalogError.decoding(underlying: error)
        }
    }

    convenience init(fileURL: URL) throws {
        try self.init(jsonData: Data(contentsOf: fileURL))
    }

    /// Loads ``Resources/FleetCommandCatalog.json`` from the GuardianHQ target bundle.
    static func loadBundled() throws -> FleetCommandCatalog {
        guard let url = Bundle.module.url(forResource: "FleetCommandCatalog", withExtension: "json") else {
            throw FleetCommandCatalogError.missingBundledCatalog
        }
        return try FleetCommandCatalog(fileURL: url)
    }

    // MARK: Lookup

    var commandNames: [String] { entries.keys.sorted() }

    func entry(named commandName: String) -> FleetCommandCatalogEntry? {
        entries[commandName]
    }

    /// Raw JSON objects for `commandName` + `vehicleClassCode` (e.g. `UAV-C`). Nil if command or class row is absent.
    func commandObjects(commandName: String, vehicleClassCode: String) -> [FleetSemanticStepJSONObject]? {
        entries[commandName]?.commands[vehicleClassCode]
    }

    // MARK: Parser (JSON objects → semantic steps)

    /// Translates a command array from JSON into ``FleetSemanticStep`` values.
    func parseSemanticSteps(_ objects: [FleetSemanticStepJSONObject]) throws -> [FleetSemanticStep] {
        try FleetSemanticStepParser.parse(commandObjects: objects)
    }

    /// Lookup + parse for one command name and vehicle class code.
    func semanticSteps(commandName: String, vehicleClassCode: String) throws -> [FleetSemanticStep] {
        guard let objects = commandObjects(commandName: commandName, vehicleClassCode: vehicleClassCode) else {
            return []
        }
        return try parseSemanticSteps(objects)
    }

    // MARK: Converter (semantic steps → stack-specific fleet commands)

    /// Converts parsed semantic steps into ``FleetVehicleCommand`` for the given autopilot stack.
    func convertToFleetVehicleCommands(_ steps: [FleetSemanticStep], stack: FleetAutopilotStack) -> [FleetVehicleCommand] {
        switch stack {
        case .px4:
            return FleetCommandCatalogStackPX4.fleetVehicleCommands(for: steps)
        case .ardupilot:
            return FleetCommandCatalogStackArduPilot.fleetVehicleCommands(for: steps)
        case .unknown:
            return []
        }
    }

    /// Lookup + parse + convert.
    func fleetVehicleCommands(commandName: String, vehicleClassCode: String, stack: FleetAutopilotStack) throws -> [FleetVehicleCommand] {
        let steps = try semanticSteps(commandName: commandName, vehicleClassCode: vehicleClassCode)
        return convertToFleetVehicleCommands(steps, stack: stack)
    }
}

// MARK: - Vehicle class codes (JSON `commands` keys)

extension FleetVehicleType {

    /// Resolves a catalog `commands` key (``FleetVehicleType/classCode``) such as `UAV-C`.
    static func fromFleetCommandCatalogClassCode(_ code: String) -> FleetVehicleType? {
        Self.allCases.first { $0.classCode == code }
    }
}
