import SwiftUI

struct FleetCalibrationControlContribution: Identifiable {
    let id: String
    let systemID: FleetCalibrationSystemID
    let makeControl: @MainActor (_ vehicle: FleetVehicleModel, _ item: FleetCalibrationItem) -> AnyView

    init<Control: View>(
        id: String,
        systemID: FleetCalibrationSystemID,
        @ViewBuilder makeControl: @escaping @MainActor (_ vehicle: FleetVehicleModel, _ item: FleetCalibrationItem) -> Control
    ) {
        self.id = id
        self.systemID = systemID
        self.makeControl = { vehicle, item in AnyView(makeControl(vehicle, item)) }
    }
}

@MainActor
enum FleetCalibrationExtensionRegistry {
    private static var pluginDefinitions: [FleetCalibrationSystemID: FleetCalibrationSystemDefinition] = [:]
    private static var pluginControls: [FleetCalibrationSystemID: [FleetCalibrationControlContribution]] = [:]

    static func registerSystemDefinition(_ definition: FleetCalibrationSystemDefinition) {
        pluginDefinitions[definition.id] = definition
    }

    static func registerControlContribution(_ contribution: FleetCalibrationControlContribution) {
        var controls = pluginControls[contribution.systemID, default: []]
        controls.removeAll { $0.id == contribution.id }
        controls.append(contribution)
        pluginControls[contribution.systemID] = controls
    }

    static func definition(for id: FleetCalibrationSystemID) -> FleetCalibrationSystemDefinition {
        pluginDefinitions[id] ?? FleetCalibrationCoreDefinitions.definition(for: id)
    }

    static func controls(
        for id: FleetCalibrationSystemID,
        vehicle: FleetVehicleModel,
        item: FleetCalibrationItem
    ) -> [AnyView] {
        pluginControls[id, default: []].map { $0.makeControl(vehicle, item) }
    }
}
