import Foundation

// MARK: - PX4 stack conversion (semantic → ``FleetVehicleCommand``)

/// PX4-specific conversion from catalog semantic steps to app-level fleet commands.
/// Diverge from ``FleetCommandCatalogStackArduPilot`` here when PX4 needs different MAVSDK / shell paths.
enum FleetCommandCatalogStackPX4: Sendable {

    static func fleetVehicleCommands(for steps: [FleetSemanticStep]) -> [FleetVehicleCommand] {
        steps.flatMap { fleetVehicleCommands(for: $0) }
    }

    static func fleetVehicleCommands(for step: FleetSemanticStep) -> [FleetVehicleCommand] {
        switch step {
        case .arm:
            return [.arm]
        case .disarm:
            return [.disarm]
        case .land:
            return [.land]
        case .returnToHome:
            return [.returnToLaunch]
        case .loiter:
            return [.holdPosition]
        case .setMode(let mode):
            return fleetVehicleCommands(setMode: mode)
        case .moveToAltitude, .moveToPoint, .setHeading, .moveInHeading:
            return []
        case .surface:
            return []
        }
    }

    private static func fleetVehicleCommands(setMode mode: FleetSemanticSetMode) -> [FleetVehicleCommand] {
        switch mode {
        case .hold, .brake:
            return [.holdPosition]
        case .manual:
            return [.idle]
        case .rtl:
            return [.returnToLaunch]
        case .landMode:
            return [.land]
        case .auto, .guided, .mission:
            return []
        }
    }
}
