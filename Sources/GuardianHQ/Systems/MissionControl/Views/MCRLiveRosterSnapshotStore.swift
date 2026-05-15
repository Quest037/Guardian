// MCRLiveRosterSnapshotStore.swift — MC-R roster strip: equatable snapshots + store to avoid redundant SwiftUI invalidation.
import Foundation
import SwiftUI

/// Reserve-swap strip semantics for one roster row (``LiveReserveSwapPickContext`` + mission template).
enum MCRLiveRosterReserveSwapStripRole: Equatable, Sendable {
    case inactive
    case pickVacancy
    case pickBenchReserve
}

/// MRE-scoped roster row inputs before fleet-cache merge (``README_FULL.md`` — MC-R live UI row contracts, assignment strip).
struct MissionRunAssignmentLiveProjection: Equatable, Sendable {
    let assignmentID: UUID
    let rosterDeviceId: UUID
    let taskId: UUID?
    /// ``MissionRunAssignmentSlotLaneMerge/preferredDisplayState`` for this slot’s lanes.
    let mergedSlotState: MissionRunAssignmentSlotState
    let attachedFleetVehicleToken: String?
    /// Cached resolved stream vehicle id (same rules as ``resolvedFleetStreamVehicleID(assignment:fleetLink:sitl:)``).
    let resolvedStreamVehicleID: String?
    let reserveSwapStripRole: MCRLiveRosterReserveSwapStripRole
    /// SITL bind id when the attached token is a SIM instance (SIM pose / preset cache key surface).
    let sitlBoundInstanceID: UUID?
}

extension MissionRunAssignmentLiveProjection {
    @MainActor
    static func make(
        assignment: MissionRunAssignment,
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        liveReserveSwapPick: LiveReserveSwapPickContext?,
        focusedLiveTaskID: UUID?
    ) -> MissionRunAssignmentLiveProjection {
        let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: assignment.effectiveSlotLifecycleLanes)
        let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
        let sitlId: UUID? = {
            guard let key = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: key),
                  case .sitl(let uuid) = token
            else { return nil }
            return uuid
        }()
        let role = reserveSwapStripRole(
            assignment: assignment,
            mission: mission,
            liveReserveSwapPick: liveReserveSwapPick,
            focusedLiveTaskID: focusedLiveTaskID
        )
        return MissionRunAssignmentLiveProjection(
            assignmentID: assignment.id,
            rosterDeviceId: assignment.rosterDeviceId,
            taskId: assignment.taskId,
            mergedSlotState: merged,
            attachedFleetVehicleToken: assignment.attachedFleetVehicleToken,
            resolvedStreamVehicleID: vid,
            reserveSwapStripRole: role,
            sitlBoundInstanceID: sitlId
        )
    }

    private static func reserveSwapStripRole(
        assignment: MissionRunAssignment,
        mission: Mission?,
        liveReserveSwapPick: LiveReserveSwapPickContext?,
        focusedLiveTaskID: UUID?
    ) -> MCRLiveRosterReserveSwapStripRole {
        guard let pick = liveReserveSwapPick,
              let mission,
              let tid = assignment.taskId ?? focusedLiveTaskID,
              tid == pick.taskID
        else { return .inactive }
        if assignment.id == pick.vacancyAssignmentID {
            return .pickVacancy
        }
        if let device = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
           device.slot == .reserve {
            return .pickBenchReserve
        }
        return .inactive
    }
}

/// Slot attention pill on a roster health card (mirrors ``MissionLiveVehicleHealthCard`` slotAttention tuple).
struct MCRLiveRosterSlotAttentionSnapshot: Equatable {
    let severity: GuardianFeedbackSeverity
    let title: String
    let help: String
}

/// Immutable UI payload for one MC-R roster health tile; compared on each hub tick so unchanged rows skip ``ObservableObject`` churn.
struct MCRLiveRosterRowSnapshot: Equatable {
    let slotTitle: String
    let rosterSubtitle: String
    let bracketedVehicleShortID: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel
    let slotAttention: MCRLiveRosterSlotAttentionSnapshot?
    let accessibilitySummary: String?
}

struct MCRLiveRosterRowPresentation: Identifiable, Equatable {
    let assignmentID: UUID
    let assignmentProjection: MissionRunAssignmentLiveProjection
    let snapshot: MCRLiveRosterRowSnapshot

    var id: UUID { assignmentID }
}

extension MCRLiveRosterRowSnapshot {
    func mergedWithFleetSlice(_ slice: MCRFleetRosterTileLiveFleetSlice) -> MCRLiveRosterRowSnapshot {
        MCRLiveRosterRowSnapshot(
            slotTitle: slotTitle,
            rosterSubtitle: rosterSubtitle,
            bracketedVehicleShortID: slice.bracketedVehicleShortID,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenames,
            vehicleClassForBundledDeviceArt: slice.vehicleClassForBundledDeviceArt,
            vehicleModel: slice.vehicleModel,
            slotAttention: slotAttention,
            accessibilitySummary: accessibilitySummary
        )
    }
}

extension MCRLiveRosterRowPresentation {
    func mergedWithLiveFleetSlice(_ slice: MCRFleetRosterTileLiveFleetSlice?) -> MCRLiveRosterRowPresentation {
        guard let slice else { return self }
        return MCRLiveRosterRowPresentation(
            assignmentID: assignmentID,
            assignmentProjection: assignmentProjection,
            snapshot: snapshot.mergedWithFleetSlice(slice)
        )
    }
}

@MainActor
enum MCRLiveRosterRowSnapshotFactory {
    private static func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        return "\(device.slot.rawValue) · \(device.behaviorRoleID)"
    }

    /// Canonical short stream label (e.g. `UAV-V:1`), aligned with roster slot cards — not raw `sysid:` keys.
    static func assignmentFleetDisplayShortID(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> String {
        guard let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else { return "" }
        if let model = fleetLink.vehicleModel(forVehicleID: vid) {
            return model.displayShortID
        }
        let rosterDeviceClass = rosterDevice?.vehicleClass ?? .unknown
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid }) {
            let systemID = inst.stackInstanceIndex + 1
            return "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
        }
        let prefix = "sysid:"
        if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
            return "\(rosterDeviceClass.classCode):\(n)"
        }
        let tail = vid.split(separator: ":").last.map(String.init) ?? vid
        return "\(rosterDeviceClass.classCode):\(tail)"
    }

    static func make(
        projection: MissionRunAssignmentLiveProjection,
        assignment: MissionRunAssignment,
        mission: Mission?,
        runStatus: MissionRunStatus,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        liveReserveSwapPick: LiveReserveSwapPickContext?,
        focusedLiveTaskID: UUID?
    ) -> MCRLiveRosterRowSnapshot {
        let device = mission.flatMap { m in
            m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
        }
        let vehicleID = projection.resolvedStreamVehicleID
        let rosterDeviceClass = device?.vehicleClass ?? .unknown
        let deviceArtVehicleClass: FleetVehicleType = {
            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.data.vehicleType
            }
            return rosterDeviceClass
        }()
        let shortRaw = assignmentFleetDisplayShortID(
            assignment: assignment,
            rosterDevice: device,
            fleetLink: fleetLink,
            sitl: sitl
        )
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        let missionLiveShowsSlotBadge = runStatus == .running || runStatus == .paused || runStatus == .recovery
        let mergedSlot = projection.mergedSlotState
        let slotAttention: MCRLiveRosterSlotAttentionSnapshot? = missionLiveShowsSlotBadge
            ? mergedSlot.missionControlRosterBadgeSeverity.map {
                MCRLiveRosterSlotAttentionSnapshot(severity: $0, title: mergedSlot.displayTitle, help: mergedSlot.rosterSlotChipHelp)
            }
            : nil
        let reserveSwapStripAccessibilitySummary: String? = {
            guard let pick = liveReserveSwapPick,
                  let mission,
                  let tid = assignment.taskId ?? focusedLiveTaskID,
                  tid == pick.taskID
            else { return nil }
            let taskName = mission.routeMacro.tasks.first { $0.id == tid }?.name ?? "Task"
            switch projection.reserveSwapStripRole {
            case .inactive:
                return nil
            case .pickVacancy:
                return MissionRunReserveSwapAccessibilityCopy.rosterVacancyDuringReserveSwapPick(
                    taskName: taskName,
                    slotName: assignment.slotName
                )
            case .pickBenchReserve:
                return MissionRunReserveSwapAccessibilityCopy.rosterBenchReserveDuringReserveSwapPick(
                    taskName: taskName,
                    slotName: assignment.slotName
                )
            }
        }()
        return MCRLiveRosterRowSnapshot(
            slotTitle: assignment.slotName,
            rosterSubtitle: rosterRoleSubtitle(device),
            bracketedVehicleShortID: bracketed,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotAttention: slotAttention,
            accessibilitySummary: reserveSwapStripAccessibilitySummary
        )
    }

    /// Builds projection then snapshot (single public entry for MC-R roster refresh).
    static func make(
        assignment: MissionRunAssignment,
        mission: Mission?,
        runStatus: MissionRunStatus,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        liveReserveSwapPick: LiveReserveSwapPickContext?,
        focusedLiveTaskID: UUID?
    ) -> MCRLiveRosterRowSnapshot {
        let projection = MissionRunAssignmentLiveProjection.make(
            assignment: assignment,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            liveReserveSwapPick: liveReserveSwapPick,
            focusedLiveTaskID: focusedLiveTaskID
        )
        return make(
            projection: projection,
            assignment: assignment,
            mission: mission,
            runStatus: runStatus,
            fleetLink: fleetLink,
            sitl: sitl,
            liveReserveSwapPick: liveReserveSwapPick,
            focusedLiveTaskID: focusedLiveTaskID
        )
    }
}

/// Publishes roster strip rows only when ``MCRLiveRosterRowPresentation`` values actually change (Equatable diff).
@MainActor
final class MCRLiveRosterSnapshotStore: ObservableObject {
    @Published private(set) var presentations: [MCRLiveRosterRowPresentation] = []

    func setPresentationsIfChanged(_ new: [MCRLiveRosterRowPresentation]) {
        if new == presentations { return }
        presentations = new
    }
}
