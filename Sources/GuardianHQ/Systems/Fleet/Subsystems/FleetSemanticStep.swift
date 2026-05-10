import Foundation

// MARK: - JSON DTO (matches objects inside each vehicle class array in FleetCommandCatalog.json)

/// One element of a vehicle-class command array in the catalog JSON.
struct FleetSemanticStepJSONObject: Codable, Equatable, Sendable {
    var step: String
    var mode: String?
    var meters: Double?
    var datum: String?
    var degrees: Double?
    var distanceM: Double?
    var headingDegrees: Double?
    var pointKind: String?
}

// MARK: - Parsed vocabulary (stack-agnostic)

enum FleetSemanticAltitudeDatum: String, CaseIterable, Sendable {
    case asl
    case msl
    case agl
}

enum FleetSemanticSetMode: String, CaseIterable, Sendable {
    case hold
    case manual
    case auto
    case rtl
    case guided
    case mission
    case landMode
    case brake
}

enum FleetSemanticMoveToPointKind: String, CaseIterable, Sendable {
    case currentLatLon
    case home
    case rally
}

enum FleetSemanticStep: Equatable, Sendable {
    case setMode(FleetSemanticSetMode)
    case arm
    case disarm
    case moveToAltitude(meters: Double, datum: FleetSemanticAltitudeDatum)
    case loiter
    case land
    case surface
    case returnToHome
    case moveToPoint(FleetSemanticMoveToPointKind)
    case setHeading(degrees: Double)
    case moveInHeading(distanceM: Double, headingDegrees: Double)
}

enum FleetSemanticStepParserError: Error, Equatable, Sendable {
    case unknownStep(String)
    case missingMode
    case unknownMode(String)
    case missingAltitudeFields
    case unknownDatum(String)
    case missingHeadingDegrees
    case missingMoveInHeadingFields
    case unknownPointKind(String)
}

/// Translates JSON command objects into ``FleetSemanticStep`` values (catalog parser stage).
enum FleetSemanticStepParser: Sendable {

    static func parse(commandObjects: [FleetSemanticStepJSONObject]) throws -> [FleetSemanticStep] {
        try commandObjects.map { try parseOne($0) }
    }

    static func parseOne(_ object: FleetSemanticStepJSONObject) throws -> FleetSemanticStep {
        let kind = object.step.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch kind {
        case "arm":
            return .arm
        case "disarm":
            return .disarm
        case "loiter":
            return .loiter
        case "land":
            return .land
        case "surface":
            return .surface
        case "returntohome", "return_to_home", "returnhome":
            return .returnToHome
        case "setmode":
            guard let rawMode = object.mode?.trimmingCharacters(in: .whitespacesAndNewlines), !rawMode.isEmpty else {
                throw FleetSemanticStepParserError.missingMode
            }
            let key = Self.normalizedSetModeKey(rawMode)
            guard let mode = FleetSemanticSetMode(rawValue: key) else {
                throw FleetSemanticStepParserError.unknownMode(object.mode ?? "")
            }
            return .setMode(mode)
        case "movetoaltitude", "move_to_altitude":
            guard let meters = object.meters, let datumRaw = object.datum else {
                throw FleetSemanticStepParserError.missingAltitudeFields
            }
            let d = datumRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let datum = FleetSemanticAltitudeDatum(rawValue: d) else {
                throw FleetSemanticStepParserError.unknownDatum(datumRaw)
            }
            return .moveToAltitude(meters: meters, datum: datum)
        case "movetopoint", "move_to_point":
            guard let raw = object.pointKind?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                throw FleetSemanticStepParserError.unknownPointKind("")
            }
            let lower = raw.lowercased()
            let resolved: FleetSemanticMoveToPointKind
            switch lower {
            case "currentlatlon", "current_lat_lon": resolved = .currentLatLon
            case "home": resolved = .home
            case "rally": resolved = .rally
            default:
                guard let k = FleetSemanticMoveToPointKind(rawValue: raw) else {
                    throw FleetSemanticStepParserError.unknownPointKind(object.pointKind ?? "")
                }
                resolved = k
            }
            return .moveToPoint(resolved)
        case "setheading", "set_heading":
            guard let deg = object.degrees else { throw FleetSemanticStepParserError.missingHeadingDegrees }
            return .setHeading(degrees: deg)
        case "moveinheading", "move_in_heading":
            guard let dist = object.distanceM, let head = object.headingDegrees else {
                throw FleetSemanticStepParserError.missingMoveInHeadingFields
            }
            return .moveInHeading(distanceM: dist, headingDegrees: head)
        default:
            throw FleetSemanticStepParserError.unknownStep(object.step)
        }
    }

    /// JSON / human entry → ``FleetSemanticSetMode/rawValue``.
    private static func normalizedSetModeKey(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "landmode", "land_mode": return "landMode"
        default: return t
        }
    }
}
