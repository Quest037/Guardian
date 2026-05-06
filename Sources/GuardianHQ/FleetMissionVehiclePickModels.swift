import Foundation

/// Stable reference to a row in the Vehicles grid (live MAVLink aircraft or a built-in SITL instance).
enum FleetMissionVehicleToken: Equatable, Hashable {
    case live
    case sitl(UUID)

    var storageKey: String {
        switch self {
        case .live: return "live"
        case .sitl(let id): return "sitl:\(id.uuidString)"
        }
    }

    init?(storageKey: String) {
        if storageKey == "live" {
            self = .live
            return
        }
        let prefix = "sitl:"
        if storageKey.hasPrefix(prefix) {
            let rest = String(storageKey.dropFirst(prefix.count))
            if let u = UUID(uuidString: rest) {
                self = .sitl(u)
                return
            }
        }
        return nil
    }
}

/// One selectable row in the mission roster vehicle sidebar (mirrors Vehicles inventory).
struct MissionPickableFleetVehicle: Identifiable {
    var id: String { token.storageKey }
    let token: FleetMissionVehicleToken
    let title: String
    /// Autopilot / stack detail (no “live” or “sim” — those are badges in the sidebar).
    let detailLine: String
    let vehicleIDText: String
    let lifecycleStatus: VehicleLifecycleStatus
    let autopilotStack: FleetAutopilotStack
    let domain: VehicleDomain
    let simulationImageBasenames: [String]?
    let isSimulation: Bool
}

@MainActor
func buildMissionPickableVehicles(
    fleetLink: FleetLinkService,
    sitl: SitlService
) -> [MissionPickableFleetVehicle] {
    var rows: [MissionPickableFleetVehicle] = []
    let simVehicleIDs = Set(
        sitl.instances.map { "sysid:\($0.stackInstanceIndex + 1)" }
    )
    let liveHardwareVehicleIDs = fleetLink.telemetryByVehicleID.keys
        .filter { !simVehicleIDs.contains($0) }
        .sorted()
    if let firstHardwareVehicleID = liveHardwareVehicleIDs.first,
       let snap = fleetLink.telemetryByVehicleID[firstHardwareVehicleID] {
        let idText = firstHardwareVehicleID.replacingOccurrences(of: "sysid:", with: "")
        rows.append(
            MissionPickableFleetVehicle(
                token: .live,
                title: "Live vehicle",
                detailLine: "\(snap.autopilotStack.displayName) · \(snap.flightMode)",
                vehicleIDText: idText,
                lifecycleStatus: .init(stage: .live),
                autopilotStack: snap.autopilotStack,
                domain: .aerial,
                simulationImageBasenames: nil,
                isSimulation: false
            )
        )
    }
    for inst in sitl.instances {
        let systemID = inst.stackInstanceIndex + 1
        let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
        let lifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID)
            ?? (inst.isAlive ? .init(stage: .awaitingTelemetry) : .init(stage: .stopped))
        rows.append(
            MissionPickableFleetVehicle(
                token: .sitl(inst.id),
                title: inst.preset.displayName,
                detailLine: inst.platform.displayName,
                vehicleIDText: "\(systemID)",
                lifecycleStatus: lifecycle,
                autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                domain: inst.preset.vehicleDomain,
                simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                isSimulation: true
            )
        )
    }
    return rows
}

@MainActor
func resolvedRosterVehicleLabel(
    assignment: MissionRunAssignment,
    fleetLink: FleetLinkService,
    sitl: SitlService
) -> String? {
    if let key = assignment.attachedFleetVehicleToken,
       let token = FleetMissionVehicleToken(storageKey: key)
    {
        switch token {
        case .live:
            if let snap = fleetLink.telemetry {
                return "Live vehicle · \(snap.flightMode)"
            }
            return assignment.attachedDevice.isEmpty ? "Live vehicle (unavailable)" : assignment.attachedDevice
        case .sitl(let uuid):
            if let inst = sitl.instances.first(where: { $0.id == uuid }) {
                let alive = inst.isAlive ? "" : " (stopped)"
                return "\(inst.preset.displayName)\(alive)"
            }
            return assignment.attachedDevice.isEmpty ? "Sim (removed)" : assignment.attachedDevice
        }
    }
    let legacy = assignment.attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines)
    return legacy.isEmpty ? nil : legacy
}

@MainActor
func simulationImageBasenamesForAssignment(
    _ assignment: MissionRunAssignment,
    sitl: SitlService
) -> [String]? {
    guard let key = assignment.attachedFleetVehicleToken,
          let token = FleetMissionVehicleToken(storageKey: key),
          case .sitl(let uuid) = token,
          let inst = sitl.instances.first(where: { $0.id == uuid })
    else { return nil }
    return inst.preset.simulationDeviceImageBasenames
}
