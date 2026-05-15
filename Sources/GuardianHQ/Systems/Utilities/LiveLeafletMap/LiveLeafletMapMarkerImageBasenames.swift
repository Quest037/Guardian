import AppKit
import Foundation

/// Resolves bundled simulation device image basenames and PNG data URLs for live map markers.
enum LiveLeafletMapMarkerImageBasenames {

    /// Stable fingerprint for a basename list (order-independent).
    static func signature(_ basenames: [String]) -> String {
        basenames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    /// Same resolution order as ``MissionControlRosterSlotCard`` bundled-art basenames.
    @MainActor
    static func resolve(
        assignment: MissionRunAssignment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> [String] {
        if let sim = simulationImageBasenamesForAssignment(assignment, sitl: sitl), !sim.isEmpty {
            return sim
        }
        let device = mission.rosterDevices.first { $0.id == assignment.rosterDeviceId }
        let rosterDeviceClass = device?.vehicleClass ?? .unknown
        if let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
           let model = fleetLink.vehicleModel(forVehicleID: vehicleID) {
            return model.data.vehicleType.defaultSimulationDeviceImageBasenames
        }
        return rosterDeviceClass.defaultSimulationDeviceImageBasenames
    }

    @MainActor
    static func encodePNGDataURL(basenames: [String]) -> String? {
        guard let image = SimulationDeviceBundleImage.nsImage(firstMatching: basenames),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
