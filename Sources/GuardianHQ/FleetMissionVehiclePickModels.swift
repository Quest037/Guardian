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
    if fleetLink.bridgePhase == .live {
        let snap = fleetLink.telemetry ?? .empty
        rows.append(
            MissionPickableFleetVehicle(
                token: .live,
                title: "Live vehicle",
                detailLine: "\(snap.autopilotStack.displayName) · \(snap.flightMode)",
                domain: .aerial,
                simulationImageBasenames: nil,
                isSimulation: false
            )
        )
    }
    for inst in sitl.instances {
        rows.append(
            MissionPickableFleetVehicle(
                token: .sitl(inst.id),
                title: inst.preset.displayName,
                detailLine: inst.platform.displayName,
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
            if fleetLink.bridgePhase == .live {
                let snap = fleetLink.telemetry ?? .empty
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
